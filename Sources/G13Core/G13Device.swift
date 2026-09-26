import Foundation
import IOKit
import IOKit.hid

/// Userspace driver for the Logitech G13, built on `IOHIDManager`.
///
/// Reads input reports on a dedicated runloop thread (so a busy main actor never
/// stalls input) and writes feature reports (backlight / LED). The G13's keys
/// are not consumed by macOS as a system keyboard, so we neither seize the
/// device nor require root; Input Monitoring permission is still required to
/// receive reports on recent macOS.
public final class G13Device {
    public static let vendorID = 0x046D
    public static let productID = 0xC21C

    /// Raw, normalized 8-byte report (always begins with the 0x01 marker).
    /// Invoked on the HID thread.
    public var onInputReport: ((Data) -> Void)?
    /// Raw report for diagnostics: (reportID, normalized bytes). HID thread.
    public var onRawReport: ((Int, [UInt8]) -> Void)?
    /// Invoked on the HID thread when the device appears / disappears.
    public var onConnected: (() -> Void)?
    public var onDisconnected: (() -> Void)?

    /// Count of input reports received (any report id), for diagnostics.
    public private(set) var reportCount = 0

    private let manager: IOHIDManager
    private let lock = NSLock()
    private var device: IOHIDDevice?
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    private let reportCapacity = 64
    private let reportBuffer: UnsafeMutablePointer<UInt8>

    public private(set) var isConnected = false

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportCapacity)
        reportBuffer.initialize(repeating: 0, count: reportCapacity)
    }

    deinit {
        reportBuffer.deinitialize(count: reportCapacity)
        reportBuffer.deallocate()
    }

    /// Start the HID thread and begin matching/reading. Idempotent.
    public func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            self.configure()
            CFRunLoopRun()
        }
        t.name = "\(Log.subsystem).hid"
        t.stackSize = 1 << 20
        thread = t
        t.start()
    }

    public func stop() {
        lock.lock()
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
        lock.unlock()
        if let runLoop {
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopStop(runLoop)
        }
        IOHIDManagerClose(manager, 0)
        isConnected = false
        thread = nil
        runLoop = nil
    }

    /// Tear down and re-open. Used when Input Monitoring is granted while running
    /// (HID delivery only begins after a fresh open once permission exists).
    public func restart() {
        stop()
        start()
    }

    // MARK: - Setup (HID thread)

    private func configure() {
        let match: [String: Any] = [
            kIOHIDVendorIDKey: G13Device.vendorID,
            kIOHIDProductIDKey: G13Device.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, deviceRef in
            guard let ctx else { return }
            Unmanaged<G13Device>.fromOpaque(ctx).takeUnretainedValue().handleMatched(deviceRef)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, deviceRef in
            guard let ctx else { return }
            Unmanaged<G13Device>.fromOpaque(ctx).takeUnretainedValue().handleRemoved(deviceRef)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, 0)
        if result != kIOReturnSuccess {
            Log.device.error("IOHIDManagerOpen failed: \(String(format: "0x%08x", result), privacy: .public)")
        }
    }

    private func handleMatched(_ deviceRef: IOHIDDevice) {
        lock.lock()
        device = deviceRef
        lock.unlock()

        // Explicitly open AND schedule the device on this run loop. Relying on
        // IOHIDManagerOpen alone is enough for SetReport (writes) but NOT
        // reliable for the input-report callback to fire.
        let openResult = IOHIDDeviceOpen(deviceRef, 0)
        if openResult != kIOReturnSuccess {
            Log.device.error("IOHIDDeviceOpen: \(String(format: "0x%08x", openResult), privacy: .public)")
        }
        IOHIDDeviceScheduleWithRunLoop(deviceRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            deviceRef, reportBuffer, reportCapacity,
            { ctx, result, _, _, reportID, report, reportLength in
                guard let ctx, result == kIOReturnSuccess else { return }
                Unmanaged<G13Device>.fromOpaque(ctx).takeUnretainedValue()
                    .deliver(reportID: Int(reportID), report: report, length: reportLength)
            }, context)

        isConnected = true
        Log.device.info("G13 connected")
        onConnected?()
    }

    private func handleRemoved(_ deviceRef: IOHIDDevice) {
        lock.lock()
        device = nil
        lock.unlock()
        isConnected = false
        Log.device.info("G13 disconnected")
        onDisconnected?()
    }

    /// Normalize the delivered report to always begin with the report-id/marker
    /// byte, so downstream always sees `[0x01, joyX, joyY, ...]` regardless of
    /// whether IOKit stripped a numbered report id.
    private func deliver(reportID: Int, report: UnsafePointer<UInt8>, length: Int) {
        var data = Data(UnsafeBufferPointer(start: report, count: length))
        // The G13's key report is id 1, 8 bytes on the wire ([0x01]+7 data).
        // IOKit may deliver it WITH the id (length 8, first byte 0x01) or WITHOUT
        // (length 7, data only). Normalize to the canonical 8-byte [0x01, ...].
        if reportID == 1, length == 7 {
            data = Data([0x01]) + data
        }
        reportCount &+= 1
        if reportCount <= 12 {
            let hex = data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
            Log.device.info("report #\(self.reportCount, privacy: .public) id=\(reportID, privacy: .public) len=\(length, privacy: .public) -> \(hex, privacy: .public)")
        }
        onRawReport?(reportID, Array(data))
        onInputReport?(data)
    }

    // MARK: - Output (any thread)

    /// Send a feature report (e.g. 0x07 backlight RGB, 0x05 M-LED bitmask).
    @discardableResult
    public func setFeatureReport(id: Int, bytes: [UInt8]) -> Bool {
        lock.lock()
        let dev = device
        lock.unlock()
        guard let dev else { return false }
        let result = bytes.withUnsafeBufferPointer { buf -> IOReturn in
            guard let base = buf.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, CFIndex(id), base, buf.count)
        }
        if result != kIOReturnSuccess {
            Log.device.error("SetReport(id=\(id)) failed: \(String(format: "0x%08x", result), privacy: .public)")
            return false
        }
        return true
    }
}

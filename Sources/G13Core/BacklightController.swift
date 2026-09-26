import Foundation

/// Drives the G13's RGB backlight (feature report 0x07) and the M1/M2/M3/MR
/// mode LEDs (feature report 0x05, bitmask 1/2/4/8).
///
/// NOTE: the exact on-wire framing of these vendor feature reports is not
/// described by a HID report descriptor. We send the report id separately with
/// an id-less payload (the documented IOHID convention); if that returns an
/// error we retry with the id embedded and an unnumbered report (the format used
/// by the libusb-based `ecraven/g13`). If the backlight doesn't respond on real
/// hardware, adjust the two byte layouts here.
@MainActor
public final class BacklightController {
    private weak var device: G13Device?
    private var lastColor: RGBColor?
    private var lastBank: Int?

    public init(device: G13Device) { self.device = device }

    public func setColor(_ color: RGBColor) {
        lastColor = color
        guard let device else { return }
        // Feature report 0x07 = 4-byte payload (R,G,B,reserved), per HID descriptor
        // (report 7, 32 bits) and ecraven/g13's {7,r,g,b,0} control payload.
        if device.setFeatureReport(id: 0x07, bytes: [color.r, color.g, color.b, 0x00]) { return }
        _ = device.setFeatureReport(id: 0x00, bytes: [0x07, color.r, color.g, color.b, 0x00])
    }

    /// Light the LED for the active bank (M1=0 … MR=3).
    public func setBankLED(_ bankIndex: Int) {
        lastBank = bankIndex
        guard let device else { return }
        let mask: UInt8 = [0x01, 0x02, 0x04, 0x08][min(max(0, bankIndex), 3)]
        // Feature report 0x05 = 4-byte payload (mask,reserved...), per descriptor
        // (report 5, 32 bits) and ecraven/g13's {5,leds,0,0,0} control payload.
        if device.setFeatureReport(id: 0x05, bytes: [mask, 0x00, 0x00, 0x00]) { return }
        _ = device.setFeatureReport(id: 0x00, bytes: [0x05, mask, 0x00, 0x00, 0x00])
    }

    /// Re-apply the last color + bank LED (e.g. after the device reconnects and
    /// forgets its state).
    public func reassert() {
        if let lastColor { setColor(lastColor) }
        if let lastBank { setBankLED(lastBank) }
    }
}

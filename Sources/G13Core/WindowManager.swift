import Foundation
import AppKit
import ApplicationServices

/// Tiles / moves the frontmost window via the Accessibility API (like Rectangle
/// or Magnet). Requires the Accessibility permission (already needed for input
/// injection). Frames are computed in Cocoa coordinates and flipped to the AX
/// top-left coordinate space when applied.
@MainActor
public final class WindowManager {
    public static let shared = WindowManager()

    /// Per-app last frame (Cocoa coords) so `.restore` can undo a tile.
    private var lastFrames: [pid_t: CGRect] = [:]

    public func perform(_ action: WindowAction) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        guard let window = focusedWindow(of: appElement) else {
            Log.action.error("WindowManager: no focused window for \(app.bundleIdentifier ?? "?", privacy: .public)")
            return
        }
        guard let axFrame = frame(of: window) else { return }
        let cocoaFrame = flipY(axFrame)
        let screen = screenContaining(cocoaFrame) ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        switch action {
        case .restore:
            if let previous = lastFrames[pid] { set(window, cocoaRect: previous) }
        case .maximize:
            // Toggle: already maximized → restore the saved frame; else maximize.
            if isMaximized(cocoaFrame, visible), let previous = lastFrames[pid] {
                set(window, cocoaRect: previous)
            } else {
                lastFrames[pid] = cocoaFrame
                set(window, cocoaRect: visible)
            }
        default:
            lastFrames[pid] = cocoaFrame
            set(window, cocoaRect: targetRect(action, in: visible))
        }
    }

    private func isMaximized(_ frame: CGRect, _ visible: CGRect) -> Bool {
        abs(frame.minX - visible.minX) < 8 && abs(frame.minY - visible.minY) < 8 &&
        abs(frame.width - visible.width) < 8 && abs(frame.height - visible.height) < 8
    }

    // MARK: - Minimize / Full Screen (robust via AX, not synthesized menu keys)

    public func minimizeFront() {
        guard let window = frontWindow() else { return }
        setBool(window, kAXMinimizedAttribute, true)
    }

    public func toggleFullScreenFront() {
        guard let window = frontWindow() else { return }
        let current = boolValue(window, "AXFullScreen") ?? false
        setBool(window, "AXFullScreen", !current)
    }

    private func frontWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedWindow(of: AXUIElementCreateApplication(app.processIdentifier))
    }

    private func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFTypeRef)
    }

    private func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? Bool
    }

    /// Cocoa-coordinate target (y grows upward, so "top" = higher y).
    private func targetRect(_ action: WindowAction, in vf: CGRect) -> CGRect {
        let w = vf.width, h = vf.height, hw = vf.width / 2, hh = vf.height / 2
        switch action {
        case .leftHalf:    return CGRect(x: vf.minX, y: vf.minY, width: hw, height: h)
        case .rightHalf:   return CGRect(x: vf.midX, y: vf.minY, width: hw, height: h)
        case .topHalf:     return CGRect(x: vf.minX, y: vf.midY, width: w, height: hh)
        case .bottomHalf:  return CGRect(x: vf.minX, y: vf.minY, width: w, height: hh)
        case .topLeft:     return CGRect(x: vf.minX, y: vf.midY, width: hw, height: hh)
        case .topRight:    return CGRect(x: vf.midX, y: vf.midY, width: hw, height: hh)
        case .bottomLeft:  return CGRect(x: vf.minX, y: vf.minY, width: hw, height: hh)
        case .bottomRight: return CGRect(x: vf.midX, y: vf.minY, width: hw, height: hh)
        case .maximize:    return vf
        case .center:      return CGRect(x: vf.midX - w * 0.35, y: vf.midY - h * 0.35,
                                         width: w * 0.7, height: h * 0.7)
        case .restore:     return vf
        }
    }

    // MARK: - AX helpers

    private func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)   // AX (top-left origin)
    }

    private func set(_ window: AXUIElement, cocoaRect: CGRect) {
        let ax = flipY(cocoaRect)
        var pos = CGPoint(x: ax.minX, y: ax.minY)
        var size = CGSize(width: ax.width, height: ax.height)
        // Set position, then size, then position again — some apps clamp mid-resize.
        if let p = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        }
        if let s = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        }
        if let p = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        }
    }

    // MARK: - Coordinate flip (AX top-left ↔ Cocoa bottom-left, symmetric)

    private func flipY(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var r = rect
        r.origin.y = primaryHeight - rect.origin.y - rect.height
        return r
    }

    private func screenContaining(_ cocoaRect: CGRect) -> NSScreen? {
        let center = CGPoint(x: cocoaRect.midX, y: cocoaRect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }
}

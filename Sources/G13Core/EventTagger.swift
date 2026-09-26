import Foundation
import CoreGraphics

/// Owns the single private `CGEventSource` used for ALL injected events, and a
/// magic marker written into each event's `eventSourceUserData`. The macro
/// recorder uses `isOurs(_:)` to ignore events we injected, preventing a
/// record→playback feedback loop.
public final class EventTagger: @unchecked Sendable {
    public static let shared = EventTagger()

    public let source: CGEventSource?
    /// Arbitrary fixed marker ("G13" + nonce) identifying our synthetic events.
    public static let magic: Int64 = 0x4731_3300_0001

    public init() {
        source = CGEventSource(stateID: .privateState)
    }

    public func tag(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: EventTagger.magic)
    }

    public func post(_ event: CGEvent, tap: CGEventTapLocation = .cghidEventTap) {
        tag(event)
        event.post(tap: tap)
    }

    public func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == EventTagger.magic
    }
}

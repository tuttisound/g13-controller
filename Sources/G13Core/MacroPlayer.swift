import Foundation

/// Replays a `Macro` by running each enabled step's `BindingAction` through the
/// shared `ActionEngine` (one-shot dispatch) on a cancelable task, pausing
/// `delayAfterMs` between steps and looping `repeatCount` times.
@MainActor
public final class MacroPlayer {
    /// Wired by `ActionEngine.init` so the player reuses the engine's injection.
    public weak var engine: ActionEngine?
    private var task: Task<Void, Never>?

    public init() {}

    public var isPlaying: Bool { task != nil && !(task?.isCancelled ?? true) }

    public func play(_ macro: Macro) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let count = max(1, macro.repeatCount)
            for _ in 0..<count {
                for step in macro.steps where step.isEnabled {
                    if Task.isCancelled { return }
                    self.engine?.performOnce(step.action)
                    let ms = step.delayAfterMs > 0 ? step.delayAfterMs : 4
                    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                }
            }
            self.task = nil
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}

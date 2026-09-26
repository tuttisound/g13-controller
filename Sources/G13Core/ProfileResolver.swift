import Foundation

/// The currently-active mapping, derived from (config, frontmost app, bank).
public struct ResolvedState: Equatable, Sendable {
    public var profileID: UUID
    public var profileName: String
    public var bankIndex: Int
    public var bankColor: RGBColor
    public var bindings: [InputID: BindingAction]

    public func binding(for id: InputID) -> BindingAction { bindings[id] ?? .none }
}

/// Pure resolution of which profile/bank applies and what its bindings are.
public enum ProfileResolver {
    public static func resolve(config: Config, bundleID: String?, bankOverride: Int? = nil) -> ResolvedState {
        let profile = config.profile(forBundleID: bundleID)
        let idx = min(max(0, bankOverride ?? profile.lastActiveBankIndex), 3)
        let bank = profile.banks.indices.contains(idx) ? profile.banks[idx] : profile.banks[0]
        return ResolvedState(profileID: profile.id,
                             profileName: profile.name,
                             bankIndex: idx,
                             bankColor: bank.color,
                             bindings: bank.bindings)
    }
}

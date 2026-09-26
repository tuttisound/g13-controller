import Foundation

/// Loads/saves `Config` as JSON under Application Support, with atomic writes, a
/// rolling backup, schema migration, and self-healing on corruption.
///
/// `~/Library/Application Support/dev.tuttisound.G13Manager/config.json`
public final class ConfigStore {
    public let directoryURL: URL
    public let fileURL: URL
    public let backupURL: URL

    public init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let appSup = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil, create: true))
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            dir = appSup.appendingPathComponent("dev.tuttisound.G13Manager", isDirectory: true)
        }
        directoryURL = dir
        fileURL = dir.appendingPathComponent("config.json")
        backupURL = dir.appendingPathComponent("config.backup.json")
    }

    // MARK: - Load

    /// Load config, recovering from backup or defaults on failure. Never throws;
    /// always returns a usable, sanitized config and ensures a file exists.
    public func load() -> Config {
        ensureDirectory()

        if let config = decode(fileURL) {
            return sanitized(migrated(config))
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            Log.config.error("config.json unreadable; trying backup")
        }

        if let backup = decode(backupURL) {
            let recovered = sanitized(migrated(backup))
            try? save(recovered)          // self-heal the primary file
            Log.config.info("recovered config from backup")
            return recovered
        }

        let fresh = ConfigStore.makeDefault()
        try? save(fresh)
        Log.config.info("created default config")
        return fresh
    }

    private func decode(_ url: URL) -> Config? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    // MARK: - Save

    public func save(_ config: Config) throws {
        ensureDirectory()
        // Roll the current good file into the backup before overwriting.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Migration & sanitation

    private func migrated(_ config: Config) -> Config {
        var c = config
        // Macro step migration (legacy → RPA `MacroStep`) happens in `Macro.init(from:)`
        // at decode time, so it's already applied here regardless of version. This
        // just stamps the current version; the next `save()` rewrites in the new shape.
        c.schemaVersion = Config.currentSchemaVersion
        return c
    }

    /// Guarantee invariants the rest of the app relies on: ≥1 profile, a valid
    /// default id, exactly 4 banks per profile, and an in-range active bank.
    private func sanitized(_ config: Config) -> Config {
        var c = config
        if c.profiles.isEmpty {
            let d = ConfigStore.makeDefault()
            c.profiles = d.profiles
            c.defaultProfileID = d.defaultProfileID
        }
        if c.profile(id: c.defaultProfileID) == nil {
            c.defaultProfileID = c.profiles[0].id
        }
        for i in c.profiles.indices {
            while c.profiles[i].banks.count < 4 {
                let n = c.profiles[i].banks.count + 1
                c.profiles[i].banks.append(Bank(name: "Bank \(n)", color: .off))
            }
            if c.profiles[i].banks.count > 4 {
                c.profiles[i].banks = Array(c.profiles[i].banks.prefix(4))
            }
            c.profiles[i].lastActiveBankIndex = min(max(0, c.profiles[i].lastActiveBankIndex), 3)
        }
        return c
    }

    // MARK: - Defaults

    public static let defaultBankColors: [RGBColor] = [
        RGBColor(r: 0, g: 90, b: 255),     // blue
        RGBColor(r: 0, g: 200, b: 70),     // green
        RGBColor(r: 255, g: 140, b: 0),    // orange
        RGBColor(r: 200, g: 0, b: 255),    // purple
    ]

    /// A default bank: joystick directions mapped to arrow keys so the stick
    /// works out of the box; G-keys left unbound for the user to assign.
    public static func makeDefaultBank(index: Int) -> Bank {
        let joy: [InputID: BindingAction] = [
            .joyUp: .keystroke(KeyChord(key: "up", repeatsWhileHeld: true)),
            .joyDown: .keystroke(KeyChord(key: "down", repeatsWhileHeld: true)),
            .joyLeft: .keystroke(KeyChord(key: "left", repeatsWhileHeld: true)),
            .joyRight: .keystroke(KeyChord(key: "right", repeatsWhileHeld: true)),
        ]
        return Bank(name: "Bank \(index + 1)",
                    color: defaultBankColors[index % defaultBankColors.count],
                    bindings: joy)
    }

    public static func makeDefaultProfile(name: String = "Default") -> Profile {
        Profile(id: UUID(), name: name, banks: (0..<4).map { makeDefaultBank(index: $0) })
    }

    public static func makeDefault() -> Config {
        let profile = makeDefaultProfile()
        return Config(profiles: [profile], apps: [],
                      defaultProfileID: profile.id, macros: [],
                      settings: GlobalSettings())
    }
}

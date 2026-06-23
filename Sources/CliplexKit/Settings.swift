import Foundation

/// Settings keys persisted in the `settings` table (shared with the prior
/// Rust/Tauri build so existing values are honored).
public enum SettingsKey {
    public static let maxHistory = "max_history"
    public static let pollIntervalMs = "poll_interval_ms"
    public static let ignoreConcealed = "ignore_concealed"
    public static let excludedApps = "excluded_apps"
    public static let pasteOnSelect = "paste_on_select"
    public static let theme = "theme"
}

/// Password managers / sensitive apps excluded by default on first run, as a
/// belt-and-suspenders complement to concealed-pasteboard-type filtering.
public let defaultExcludedApps: [String] = [
    "com.agilebits.onepassword7",
    "com.1password.1password",
    "com.bitwarden.desktop",
    "com.lastpass.LastPass",
    "org.keepassxc.keepassxc",
    "in.sinew.Enpass-Desktop",
    "com.apple.keychainaccess",
]

/// User-selectable appearance.
public enum Appearance: String, CaseIterable, Sendable {
    case system
    case dark
    case light
}

/// Effective runtime configuration, derived from persisted settings. Mirrors
/// the Rust `RuntimeConfig` so behavior matches the previous build.
public struct AppSettings: Equatable, Sendable {
    public var maxHistory: Int64
    public var pollIntervalMs: Int
    public var ignoreConcealed: Bool
    public var excludedApps: [String]
    public var pasteOnSelect: Bool
    public var theme: Appearance

    public init(
        maxHistory: Int64 = 500,
        pollIntervalMs: Int = 500,
        ignoreConcealed: Bool = true,
        excludedApps: [String] = [],
        pasteOnSelect: Bool = true,
        theme: Appearance = .system
    ) {
        self.maxHistory = maxHistory
        self.pollIntervalMs = pollIntervalMs
        self.ignoreConcealed = ignoreConcealed
        self.excludedApps = excludedApps
        self.pasteOnSelect = pasteOnSelect
        self.theme = theme
    }

    /// The capture filter derived from these settings.
    public var captureConfig: CaptureConfig {
        CaptureConfig(ignoreConcealed: ignoreConcealed, excludedApps: excludedApps)
    }

    /// Builds settings from persisted values, falling back to defaults for any
    /// missing or malformed entry. On first run the curated password-manager
    /// exclusion list is seeded.
    public static func load(from store: ClipStore) -> AppSettings {
        var settings = AppSettings()
        if let raw = try? store.setting(SettingsKey.maxHistory), let value = Int64(raw) {
            settings.maxHistory = min(max(value, 10), 100_000)
        }
        if let raw = try? store.setting(SettingsKey.pollIntervalMs), let value = Int(raw) {
            settings.pollIntervalMs = min(max(value, 100), 5_000)
        }
        if let raw = try? store.setting(SettingsKey.ignoreConcealed) {
            settings.ignoreConcealed = raw != "false"
        }
        if let raw = try? store.setting(SettingsKey.excludedApps) {
            settings.excludedApps = parseExcluded(raw)
        } else {
            settings.excludedApps = defaultExcludedApps
        }
        if let raw = try? store.setting(SettingsKey.pasteOnSelect) {
            settings.pasteOnSelect = raw != "false"
        }
        if let raw = try? store.setting(SettingsKey.theme),
           let appearance = Appearance(rawValue: raw) {
            settings.theme = appearance
        }
        return settings
    }

    /// Persists all settings.
    public func save(to store: ClipStore) throws {
        try store.setSetting(SettingsKey.maxHistory, String(maxHistory))
        try store.setSetting(SettingsKey.pollIntervalMs, String(pollIntervalMs))
        try store.setSetting(SettingsKey.ignoreConcealed, ignoreConcealed ? "true" : "false")
        try store.setSetting(SettingsKey.excludedApps, excludedApps.joined(separator: "\n"))
        try store.setSetting(SettingsKey.pasteOnSelect, pasteOnSelect ? "true" : "false")
        try store.setSetting(SettingsKey.theme, theme.rawValue)
    }
}

/// Parses a newline/comma-separated list of excluded app identifiers.
public func parseExcluded(_ raw: String) -> [String] {
    raw.split(whereSeparator: { $0 == "\n" || $0 == "," })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

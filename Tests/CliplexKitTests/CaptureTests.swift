import Foundation
import Testing
@testable import CliplexKit

@Suite struct CaptureTests {
    private func cap(_ text: String, concealed: Bool = false, app: String? = nil) -> Captured {
        Captured(
            kind: .text,
            preview: text,
            concealed: concealed,
            sourceApp: app,
            assets: [ClipAsset(uti: UTI.text, bytes: Data(text.utf8))]
        )
    }

    @Test func storesNormalText() {
        #expect(shouldStore(cap("hello"), config: CaptureConfig()))
    }

    @Test func skipsEmpty() {
        #expect(!shouldStore(cap("   "), config: CaptureConfig()))
    }

    @Test func skipsConcealedByDefault() {
        #expect(!shouldStore(cap("secret", concealed: true), config: CaptureConfig()))
    }

    @Test func keepsConcealedWhenDisabled() {
        #expect(shouldStore(cap("secret", concealed: true),
                            config: CaptureConfig(ignoreConcealed: false)))
    }

    @Test func skipsExcludedAppCaseInsensitive() {
        let config = CaptureConfig(excludedApps: ["com.apple.keychainaccess"])
        #expect(!shouldStore(cap("pw", app: "com.apple.KeychainAccess"), config: config))
        #expect(shouldStore(cap("ok", app: "com.other.app"), config: config))
    }

    @Test func detectsHexColors() {
        #expect(detectHexColor("#4d9bff"))
        #expect(detectHexColor("  #FFF  "))
        #expect(!detectHexColor("hello"))
        #expect(!detectHexColor("#12"))
        #expect(!detectHexColor("#gggggg"))
    }

    @Test func nonTextAssetIsNotEmptyEvenWithBlankPreview() {
        // An image accompanied by a blank-but-present text placeholder must not
        // be treated as empty (otherwise the whole clip — including the image —
        // would be discarded).
        let imageClip = Captured(
            kind: .image,
            preview: "(Image)",
            concealed: false,
            sourceApp: nil,
            assets: [
                ClipAsset(uti: UTI.text, bytes: Data("  ".utf8)),
                ClipAsset(uti: UTI.png, bytes: Data([0x89, 0x50]))
            ]
        )
        #expect(!imageClip.isEmpty)
        #expect(shouldStore(imageClip, config: CaptureConfig()))
    }

    @Test func blankTextOnlyIsEmpty() {
        let blank = Captured(
            kind: .text, preview: "  \n", concealed: false, sourceApp: nil,
            assets: [ClipAsset(uti: UTI.text, bytes: Data("  \n".utf8))]
        )
        #expect(blank.isEmpty)
    }
}

@Suite struct SettingsTests {
    @Test func defaultsOnFreshStore() throws {
        let store = try ClipStore()
        let settings = AppSettings.load(from: store)
        #expect(settings.maxHistory == 500)
        #expect(settings.pollIntervalMs == 500)
        #expect(settings.ignoreConcealed)
        #expect(settings.pasteOnSelect)
        #expect(settings.theme == .system)
        // First run seeds the curated exclusion list.
        #expect(settings.excludedApps == defaultExcludedApps)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = try ClipStore()
        var settings = AppSettings()
        settings.maxHistory = 42
        settings.pollIntervalMs = 250
        settings.ignoreConcealed = false
        settings.excludedApps = ["com.x", "com.y"]
        settings.pasteOnSelect = false
        settings.theme = .dark
        settings.clearHistoryOnQuit = true
        try settings.save(to: store)

        let loaded = AppSettings.load(from: store)
        #expect(loaded == settings)
    }

    @Test func clampsOutOfRangeValues() throws {
        let store = try ClipStore()
        try store.setSetting(SettingsKey.maxHistory, "5")
        try store.setSetting(SettingsKey.pollIntervalMs, "10")
        let low = AppSettings.load(from: store)
        #expect(low.maxHistory == 10)
        #expect(low.pollIntervalMs == 100)

        try store.setSetting(SettingsKey.maxHistory, "999999")
        try store.setSetting(SettingsKey.pollIntervalMs, "99999")
        let high = AppSettings.load(from: store)
        #expect(high.maxHistory == 100_000)
        #expect(high.pollIntervalMs == 5_000)
    }

    @Test func parsesExcludedWithMixedSeparators() {
        #expect(parseExcluded("com.a , com.b\ncom.c\n\n") == ["com.a", "com.b", "com.c"])
    }
}

import AppKit

/// Native macOS clipboard access using `NSPasteboard`.
///
/// * Change detection uses the pasteboard `changeCount` (cheap; no polling of
///   content).
/// * Reads plain text, RTF, and PNG/TIFF images, and flags concealed/secret
///   clips via the `org.nspasteboard.*` type conventions.
/// * Active-app detection uses `NSWorkspace.frontmostApplication`.
public final class MacClipboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// A token that changes whenever the clipboard content changes.
    public var changeToken: Int {
        pasteboard.changeCount
    }

    /// Reads the current clipboard content, or `nil` when it is empty.
    ///
    /// The clip's `kind` is decided from the captured assets (not from the text
    /// branch alone), so an image accompanied by a blank-but-present text
    /// placeholder is still stored and labeled as an image rather than dropped.
    public func read() -> Captured? {
        guard let types = pasteboard.types, !types.isEmpty else { return nil }
        let typeStrings = types.map(\.rawValue)
        let concealed = typeStrings.contains { raw in
            concealedPasteboardTypes.contains { $0.caseInsensitiveCompare(raw) == .orderedSame }
        }

        var assets: [ClipAsset] = []
        var text: String?
        var hasRTF = false
        var hasImage = false

        if let value = pasteboard.string(forType: .string), !value.isEmpty {
            text = value
            assets.append(ClipAsset(uti: UTI.text, bytes: Data(value.utf8), idx: Int64(assets.count)))
        }
        if let rtf = pasteboard.data(forType: .rtf), !rtf.isEmpty {
            hasRTF = true
            assets.append(ClipAsset(uti: UTI.rtf, bytes: rtf, idx: Int64(assets.count)))
        }
        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            hasImage = true
            assets.append(ClipAsset(uti: UTI.png, bytes: png, idx: Int64(assets.count)))
        } else if let tiff = pasteboard.data(forType: .tiff), !tiff.isEmpty {
            hasImage = true
            assets.append(ClipAsset(uti: UTI.tiff, bytes: tiff, idx: Int64(assets.count)))
        }

        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind: ClipKind
        let preview: String
        if !trimmed.isEmpty {
            preview = text!
            if detectHexColor(text!) { kind = .color }
            else if hasRTF { kind = .richtext }
            else { kind = .text }
        } else if hasImage {
            kind = .image
            preview = "(Image)"
        } else if hasRTF {
            kind = .richtext
            preview = "(Rich text)"
        } else if let files = readFileURLs() {
            // A Finder/file copy (no text/image): store the file references.
            return Captured(
                kind: .files,
                preview: files.names,
                concealed: concealed,
                sourceApp: activeApp(),
                assets: files.assets
            )
        } else {
            return nil
        }

        return Captured(
            kind: kind,
            preview: preview,
            concealed: concealed,
            sourceApp: activeApp(),
            assets: assets
        )
    }

    /// Reads file-URL pasteboard items as `.fileURL` assets, if present.
    private func readFileURLs() -> (assets: [ClipAsset], names: String)? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else {
            return nil
        }
        let assets = urls.enumerated().map { index, url in
            ClipAsset(uti: UTI.fileURL, bytes: Data(url.absoluteString.utf8), idx: Int64(index))
        }
        let names = urls.map(\.lastPathComponent).joined(separator: ", ")
        return (assets, names)
    }

    /// Writes the given format payloads to the clipboard.
    @discardableResult
    public func write(_ assets: [ClipAsset]) -> Bool {
        pasteboard.clearContents()

        // File clips are written as URL objects so ⌘V pastes the files.
        let fileURLs = assets
            .filter { $0.uti == UTI.fileURL }
            .compactMap { URL(string: String(decoding: $0.bytes, as: UTF8.self)) }
        if !fileURLs.isEmpty {
            return pasteboard.writeObjects(fileURLs as [NSURL])
        }

        var wrote = false
        for asset in assets {
            switch asset.uti {
            case UTI.text:
                let value = String(decoding: asset.bytes, as: UTF8.self)
                wrote = pasteboard.setString(value, forType: .string) || wrote
            case UTI.rtf:
                wrote = pasteboard.setData(asset.bytes, forType: .rtf) || wrote
            case UTI.png:
                wrote = pasteboard.setData(asset.bytes, forType: .png) || wrote
            case UTI.tiff:
                wrote = pasteboard.setData(asset.bytes, forType: .tiff) || wrote
            default:
                break
            }
        }
        return wrote
    }

    /// Returns the bundle id / name of the frontmost application, if available.
    public func activeApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return app.bundleIdentifier ?? app.localizedName
    }
}

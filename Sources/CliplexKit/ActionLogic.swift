import Foundation
import CryptoKit

/// Pure, UI-independent logic for running quick actions: clipboard transforms
/// and `{clipboard}`-template expansion. Side effects (opening URLs/apps,
/// writing the pasteboard) live in the app layer; everything here is
/// deterministic and unit-tested.
public enum ActionLogic {
    /// The placeholder, anywhere in an action's `value`, that is replaced with
    /// the current clipboard text.
    public static let clipboardPlaceholder = "{clipboard}"

    /// Expands `{clipboard}` occurrences in `template` with `clipboard`.
    ///
    /// When `urlEncoded` is true (URL actions) the substituted text is
    /// percent-encoded so it is safe inside a query/path; otherwise it is
    /// inserted verbatim (app ids, file paths).
    public static func expand(_ template: String, clipboard: String, urlEncoded: Bool) -> String {
        guard template.contains(clipboardPlaceholder) else { return template }
        let replacement = urlEncoded
            ? (clipboard.addingPercentEncoding(withAllowedCharacters: urlValueAllowed) ?? "")
            : clipboard
        return template.replacingOccurrences(of: clipboardPlaceholder, with: replacement)
    }

    /// Whether `value` references the clipboard placeholder.
    public static func usesClipboard(_ value: String) -> Bool {
        value.contains(clipboardPlaceholder)
    }

    /// Builds the URL to open for an `openURL` action, expanding `{clipboard}`.
    /// Returns `nil` when the result isn't a valid *absolute* URL — a bare host
    /// like `github.com` (no scheme) is rejected so the caller can report it
    /// rather than silently failing to open anything.
    public static func resolvedURL(template: String, clipboard: String) -> URL? {
        let expanded = expand(template, clipboard: clipboard, urlEncoded: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expanded.isEmpty else { return nil }
        guard let url = URL(string: expanded), url.scheme != nil else { return nil }
        return url
    }

    /// Applies a clipboard transform to `input`. Returns `nil` when the input is
    /// not valid for the transform (e.g. malformed Base64/JSON), so the caller
    /// can surface a friendly error instead of corrupting the clipboard.
    public static func apply(_ transform: ActionTransform, to input: String) -> String? {
        switch transform {
        case .uppercase:
            return input.uppercased()
        case .lowercase:
            return input.lowercased()
        case .titlecase:
            return input.capitalized
        case .trim:
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decoded = String(data: data, encoding: .utf8) else { return nil }
            return decoded
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: urlValueAllowed)
        case .urlDecode:
            return input.removingPercentEncoding
        case .jsonPretty:
            return reformatJSON(input, pretty: true)
        case .jsonMinify:
            return reformatJSON(input, pretty: false)
        case .sha256:
            return sha256Hex(input)
        }
    }

    // MARK: - Helpers

    /// Characters left unescaped when substituting into a URL. Excludes the
    /// sub-delimiters and reserved characters so the clipboard text is treated
    /// as a single value rather than altering the URL's structure.
    private static let urlValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func reformatJSON(_ input: String, pretty: Bool) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: options) else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

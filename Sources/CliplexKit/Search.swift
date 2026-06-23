import Foundation

/// Helpers for building safe SQLite FTS5 `MATCH` queries from raw user input.
public enum Search {
    /// Builds a prefix-matching FTS5 query string from free-form user input.
    ///
    /// Each whitespace-separated token is wrapped in double quotes (with
    /// embedded quotes doubled) and given a trailing `*` so that typing filters
    /// results as-you-type. Returns `nil` when the input has no usable tokens,
    /// in which case the caller should fall back to a plain (unfiltered)
    /// listing.
    public static func buildFTSQuery(_ input: String) -> String? {
        let terms = input
            .split(whereSeparator: { $0.isWhitespace })
            .map { token -> String in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }
}

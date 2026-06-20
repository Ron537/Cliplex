//! Helpers for building safe SQLite FTS5 `MATCH` queries from raw user input.

/// Builds a prefix-matching FTS5 query string from free-form user input.
///
/// Each whitespace-separated token is wrapped in double quotes (with embedded
/// quotes doubled) and given a trailing `*` so that typing filters results
/// as-you-type. Returns `None` when the input has no usable tokens, in which
/// case the caller should fall back to a plain (unfiltered) listing.
///
/// # Examples
/// ```
/// use cliplex_core::search::build_fts_query;
/// assert_eq!(build_fts_query("foo ba").as_deref(), Some("\"foo\"* \"ba\"*"));
/// assert_eq!(build_fts_query("  "), None);
/// assert_eq!(build_fts_query("a\"b").as_deref(), Some("\"a\"\"b\"*"));
/// ```
pub fn build_fts_query(input: &str) -> Option<String> {
    let mut terms: Vec<String> = Vec::new();
    for token in input.split_whitespace() {
        let escaped = token.replace('"', "\"\"");
        if escaped.is_empty() {
            continue;
        }
        terms.push(format!("\"{escaped}\"*"));
    }
    if terms.is_empty() {
        None
    } else {
        Some(terms.join(" "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_input_yields_none() {
        assert_eq!(build_fts_query(""), None);
        assert_eq!(build_fts_query("   \t"), None);
    }

    #[test]
    fn tokens_are_prefix_matched() {
        assert_eq!(build_fts_query("hello"), Some("\"hello\"*".to_string()));
        assert_eq!(
            build_fts_query("hello world"),
            Some("\"hello\"* \"world\"*".to_string())
        );
    }

    #[test]
    fn quotes_are_escaped() {
        assert_eq!(build_fts_query("a\"b"), Some("\"a\"\"b\"*".to_string()));
    }
}

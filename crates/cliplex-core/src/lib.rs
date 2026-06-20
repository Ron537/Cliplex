//! Cliplex core library.
//!
//! OS-agnostic building blocks for the Cliplex clipboard manager: data models,
//! SQLite + FTS5 storage, search, deduplication, and history pruning.
//!
//! This crate intentionally has **no network dependencies** — Cliplex collects
//! no telemetry and never phones home.

/// Returns the semantic version of the core crate.
pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_reported() {
        assert!(!version().is_empty());
    }
}

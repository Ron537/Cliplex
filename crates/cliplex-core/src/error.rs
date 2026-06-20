//! Error types for the Cliplex core.

/// Result alias used throughout the core crate.
pub type Result<T> = std::result::Result<T, Error>;

/// Errors raised by the core storage and search layer.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Underlying SQLite error.
    #[error("database error: {0}")]
    Sqlite(#[from] rusqlite::Error),

    /// A requested entity did not exist.
    #[error("not found")]
    NotFound,

    /// Invalid input supplied by the caller.
    #[error("invalid input: {0}")]
    Invalid(String),
}

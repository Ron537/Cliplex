//! Cliplex platform layer.
//!
//! Defines OS-agnostic traits for the parts of a clipboard manager that must
//! talk to the operating system, with per-OS implementations to be added:
//!
//! * **Clipboard monitoring** — observe clipboard changes and read all
//!   available formats (text, RTF/HTML, image, file URLs).
//! * **Concealed-type detection** — recognise password-manager / "concealed" /
//!   transient clips so they can be skipped (privacy by default).
//! * **Active-app detection** — identify the frontmost app to support the
//!   user's app-exclusion list.
//! * **Paste injection** — write a clip to the clipboard and synthesize the
//!   platform paste shortcut.

use std::fmt;

/// A snapshot of the clipboard at a moment in time.
#[derive(Debug, Clone, Default)]
pub struct ClipboardSnapshot {
    /// Monotonic change counter (where the OS provides one).
    pub change_id: u64,
    /// Whether the source marked this clip as concealed / secret / transient.
    pub concealed: bool,
    /// Bundle id / executable name of the app that produced the clip, if known.
    pub source_app: Option<String>,
}

/// Errors raised by the platform layer.
#[derive(Debug, thiserror::Error)]
pub enum PlatformError {
    #[error("operation not supported on this platform yet")]
    Unsupported,
    #[error("platform error: {0}")]
    Other(String),
}

/// Abstraction over OS clipboard monitoring and injection.
///
/// Concrete implementations (macOS / Windows / Linux) are added in later
/// milestones behind this trait so the rest of the app stays OS-agnostic.
pub trait ClipboardBackend: Send + Sync {
    /// Returns the current clipboard change snapshot.
    fn poll(&self) -> Result<ClipboardSnapshot, PlatformError>;

    /// Returns the bundle id / name of the frontmost application, if available.
    fn active_app(&self) -> Result<Option<String>, PlatformError>;
}

/// Name of the current target platform, used for diagnostics.
pub fn target_os() -> &'static str {
    std::env::consts::OS
}

impl fmt::Display for ClipboardSnapshot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ClipboardSnapshot(change_id={}, concealed={})",
            self.change_id, self.concealed
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn target_os_known() {
        assert!(!target_os().is_empty());
    }
}

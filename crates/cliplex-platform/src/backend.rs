//! Per-OS backend selection.

use crate::ClipboardBackend;

#[cfg(target_os = "macos")]
mod macos;

#[cfg(not(target_os = "macos"))]
mod generic;

/// Constructs the clipboard backend for the current platform.
pub fn backend() -> Box<dyn ClipboardBackend> {
    #[cfg(target_os = "macos")]
    {
        Box::new(macos::MacBackend::new())
    }
    #[cfg(not(target_os = "macos"))]
    {
        Box::new(generic::GenericBackend::new())
    }
}

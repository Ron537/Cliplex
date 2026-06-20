//! Synthesizes the platform paste shortcut (Cmd+V / Ctrl+V) so a selected clip
//! is pasted into the frontmost application.
//!
//! Requires Accessibility permission on macOS (see [`crate::accessibility`]) and
//! uninhibited input simulation on Linux (X11; Wayland may require a compositor
//! helper). This function never shows a permission prompt itself — callers
//! should check [`crate::is_trusted`] first and prompt via
//! [`crate::prompt_for_trust`] when needed.

use enigo::{
    Direction::{Click, Press, Release},
    Enigo, Key, Keyboard, Settings,
};

use crate::{PlatformError, Result};

fn map_err(e: impl std::fmt::Display) -> PlatformError {
    PlatformError::Other(e.to_string())
}

/// Sends the platform paste keystroke to the frontmost app.
///
/// On macOS this must be called on the **main thread** (the keyboard-layout
/// lookup uses Text Input Source APIs that assert main-thread affinity).
pub fn inject_paste() -> Result<()> {
    if !crate::is_trusted() {
        return Err(PlatformError::NotTrusted);
    }

    // We gate on trust ourselves, so disable enigo's own permission prompt to
    // avoid showing the system dialog on every paste.
    let settings = Settings {
        open_prompt_to_get_permissions: false,
        ..Settings::default()
    };
    let mut enigo = Enigo::new(&settings).map_err(map_err)?;

    #[cfg(target_os = "macos")]
    let modifier = Key::Meta;
    #[cfg(not(target_os = "macos"))]
    let modifier = Key::Control;

    enigo.key(modifier, Press).map_err(map_err)?;
    enigo.key(Key::Unicode('v'), Click).map_err(map_err)?;
    enigo.key(modifier, Release).map_err(map_err)?;
    Ok(())
}

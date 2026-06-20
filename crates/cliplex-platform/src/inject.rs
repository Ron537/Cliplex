//! Synthesizes the platform paste shortcut (Cmd+V / Ctrl+V) so a selected clip
//! is pasted into the frontmost application.
//!
//! Requires Accessibility permission on macOS and uninhibited input simulation
//! on Linux (X11; Wayland may require a compositor helper).

use enigo::{
    Direction::{Click, Press, Release},
    Enigo, Key, Keyboard, Settings,
};

use crate::{PlatformError, Result};

fn map_err(e: impl std::fmt::Display) -> PlatformError {
    PlatformError::Other(e.to_string())
}

/// Sends the platform paste keystroke to the frontmost app.
pub fn inject_paste() -> Result<()> {
    let mut enigo = Enigo::new(&Settings::default()).map_err(map_err)?;

    #[cfg(target_os = "macos")]
    let modifier = Key::Meta;
    #[cfg(not(target_os = "macos"))]
    let modifier = Key::Control;

    enigo.key(modifier, Press).map_err(map_err)?;
    enigo.key(Key::Unicode('v'), Click).map_err(map_err)?;
    enigo.key(modifier, Release).map_err(map_err)?;
    Ok(())
}

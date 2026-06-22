//! Synthesizes the platform paste shortcut (Cmd+V / Ctrl+V) so a selected clip
//! is pasted into the frontmost application.
//!
//! Requires Accessibility permission on macOS (see [`crate::accessibility`]) and
//! uninhibited input simulation on Linux (X11; Wayland may require a compositor
//! helper). This function never shows a permission prompt itself — callers
//! should check [`crate::is_trusted`] first and prompt via
//! [`crate::prompt_for_trust`] when needed.

use crate::Result;

/// Sends the platform paste keystroke to the frontmost app.
///
/// On macOS this must be called on the **main thread** (the keyboard-layout
/// lookup uses Text Input Source APIs that assert main-thread affinity).
pub fn inject_paste() -> Result<()> {
    if !crate::is_trusted() {
        return Err(crate::PlatformError::NotTrusted);
    }
    imp::paste()
}

#[cfg(target_os = "macos")]
mod imp {
    //! Native Cmd+V via Quartz events.
    //!
    //! We post key-down/key-up for the `V` key with the Command flag set
    //! *directly on the key events* rather than synthesizing a separate
    //! Command press/release (as `enigo` does). Posting the modifier as a
    //! distinct event is racy on modern macOS — the flag can leak or arrive out
    //! of order, so the target app sees a bare keystroke (e.g. a stray
    //! "select all") instead of a paste. Setting the flag on the key event
    //! itself is atomic and is what native clipboard managers do.

    use core_graphics::event::{CGEvent, CGEventFlags, CGEventTapLocation};
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

    use crate::{PlatformError, Result};

    /// Virtual key code for `V` (`kVK_ANSI_V`).
    const KEY_V: u16 = 0x09;

    fn event_err(what: &str) -> PlatformError {
        PlatformError::Other(format!("failed to create {what}"))
    }

    pub fn paste() -> Result<()> {
        let source = CGEventSource::new(CGEventSourceStateID::CombinedSessionState)
            .map_err(|()| event_err("event source"))?;

        let key_down = CGEvent::new_keyboard_event(source.clone(), KEY_V, true)
            .map_err(|()| event_err("key-down event"))?;
        key_down.set_flags(CGEventFlags::CGEventFlagCommand);
        key_down.post(CGEventTapLocation::HID);

        let key_up = CGEvent::new_keyboard_event(source, KEY_V, false)
            .map_err(|()| event_err("key-up event"))?;
        key_up.set_flags(CGEventFlags::CGEventFlagCommand);
        key_up.post(CGEventTapLocation::HID);
        Ok(())
    }
}

#[cfg(not(target_os = "macos"))]
mod imp {
    use enigo::{
        Direction::{Click, Press, Release},
        Enigo, Key, Keyboard, Settings,
    };

    use crate::{PlatformError, Result};

    fn map_err(e: impl std::fmt::Display) -> PlatformError {
        PlatformError::Other(e.to_string())
    }

    pub fn paste() -> Result<()> {
        // We gate on trust ourselves, so disable enigo's own permission prompt.
        let settings = Settings {
            open_prompt_to_get_permissions: false,
            ..Settings::default()
        };
        let mut enigo = Enigo::new(&settings).map_err(map_err)?;
        let modifier = Key::Control;
        enigo.key(modifier, Press).map_err(map_err)?;
        enigo.key(Key::Unicode('v'), Click).map_err(map_err)?;
        enigo.key(modifier, Release).map_err(map_err)?;
        Ok(())
    }
}

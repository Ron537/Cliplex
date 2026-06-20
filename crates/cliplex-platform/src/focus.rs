//! Tracking and restoring the previously-frontmost application.
//!
//! Opening the Cliplex panel makes Cliplex the active app, stealing focus from
//! whatever the user was typing in. To paste back into that app we capture its
//! process id *before* showing the panel, then re-activate it just before
//! synthesizing the paste keystroke.
//!
//! On non-macOS platforms these are best-effort no-ops for now (the panel
//! hide() typically returns focus to the previous window).

#[cfg(target_os = "macos")]
mod imp {
    use objc2_app_kit::{NSApplicationActivationOptions, NSRunningApplication, NSWorkspace};

    /// Returns the process id of the frontmost application, if any.
    pub fn frontmost_pid() -> Option<i32> {
        let ws = NSWorkspace::sharedWorkspace();
        let app = ws.frontmostApplication()?;
        Some(app.processIdentifier())
    }

    /// Brings the application with the given pid back to the foreground.
    pub fn activate_pid(pid: i32) -> bool {
        match NSRunningApplication::runningApplicationWithProcessIdentifier(pid) {
            Some(app) => {
                app.activateWithOptions(NSApplicationActivationOptions::ActivateAllWindows)
            }
            None => false,
        }
    }
}

#[cfg(not(target_os = "macos"))]
mod imp {
    pub fn frontmost_pid() -> Option<i32> {
        None
    }
    pub fn activate_pid(_pid: i32) -> bool {
        false
    }
}

/// Process id of the frontmost application, if available.
pub fn frontmost_pid() -> Option<i32> {
    imp::frontmost_pid()
}

/// Re-activates the application with the given pid. Returns whether it was found.
pub fn activate_pid(pid: i32) -> bool {
    imp::activate_pid(pid)
}

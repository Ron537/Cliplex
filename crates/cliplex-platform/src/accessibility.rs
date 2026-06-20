//! macOS Accessibility (AX) trust checks.
//!
//! Synthesizing keystrokes requires the app to be trusted for Accessibility.
//! These helpers let the app check trust *without* prompting (so it can decide
//! whether to inject) and trigger the system prompt at most when needed —
//! avoiding the "popup on every paste" loop.
//!
//! On non-macOS platforms there is no AX concept: [`is_trusted`] returns `true`
//! and [`prompt_for_trust`] is a no-op.

#[cfg(target_os = "macos")]
mod imp {
    use core_foundation::base::TCFType;
    use core_foundation::boolean::CFBoolean;
    use core_foundation::dictionary::{CFDictionary, CFDictionaryRef};
    use core_foundation::string::{CFString, CFStringRef};

    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
        fn AXIsProcessTrustedWithOptions(options: CFDictionaryRef) -> bool;
        static kAXTrustedCheckOptionPrompt: CFStringRef;
    }

    /// Returns whether this process is trusted for Accessibility (no prompt).
    pub fn is_trusted() -> bool {
        unsafe { AXIsProcessTrusted() }
    }

    /// Triggers the system Accessibility prompt if the app is not yet trusted.
    pub fn prompt_for_trust() {
        unsafe {
            let key = CFString::wrap_under_get_rule(kAXTrustedCheckOptionPrompt);
            let value = CFBoolean::true_value();
            let options = CFDictionary::from_CFType_pairs(&[(key.as_CFType(), value.as_CFType())]);
            AXIsProcessTrustedWithOptions(options.as_concrete_TypeRef());
        }
    }
}

#[cfg(not(target_os = "macos"))]
mod imp {
    pub fn is_trusted() -> bool {
        true
    }
    pub fn prompt_for_trust() {}
}

/// Returns whether keystroke injection is permitted (Accessibility trust on
/// macOS; always `true` elsewhere). Does not prompt.
pub fn is_trusted() -> bool {
    imp::is_trusted()
}

/// Requests Accessibility trust, showing the system prompt on macOS if needed.
pub fn prompt_for_trust() {
    imp::prompt_for_trust()
}

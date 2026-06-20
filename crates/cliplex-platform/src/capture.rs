//! Capture filtering: decides whether a captured clip should be stored.
//!
//! Keeps the policy (privacy-by-default) in one pure, well-tested place so the
//! background monitor stays a thin loop.

use crate::Captured;

/// Configuration for the capture filter.
#[derive(Debug, Clone)]
pub struct CaptureConfig {
    /// Skip clips marked concealed/secret/transient by their source app.
    pub ignore_concealed: bool,
    /// Bundle ids / app names whose clips should never be stored.
    pub excluded_apps: Vec<String>,
}

impl Default for CaptureConfig {
    fn default() -> Self {
        CaptureConfig {
            ignore_concealed: true,
            excluded_apps: Vec::new(),
        }
    }
}

/// Returns `true` when the captured clip should be stored in history.
pub fn should_store(captured: &Captured, cfg: &CaptureConfig) -> bool {
    if captured.is_empty() {
        return false;
    }
    if cfg.ignore_concealed && captured.concealed {
        return false;
    }
    if let Some(app) = &captured.source_app {
        if cfg
            .excluded_apps
            .iter()
            .any(|e| e.eq_ignore_ascii_case(app))
        {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::UTI_TEXT;
    use cliplex_core::{ClipAsset, ClipKind};

    fn cap(text: &str, concealed: bool, app: Option<&str>) -> Captured {
        Captured {
            kind: ClipKind::Text,
            preview: text.to_string(),
            concealed,
            source_app: app.map(|s| s.to_string()),
            assets: vec![ClipAsset {
                uti: UTI_TEXT.to_string(),
                bytes: text.as_bytes().to_vec(),
                idx: 0,
            }],
        }
    }

    #[test]
    fn stores_normal_text() {
        assert!(should_store(
            &cap("hello", false, None),
            &CaptureConfig::default()
        ));
    }

    #[test]
    fn skips_empty() {
        assert!(!should_store(
            &cap("   ", false, None),
            &CaptureConfig::default()
        ));
    }

    #[test]
    fn skips_concealed_by_default() {
        assert!(!should_store(
            &cap("secret", true, None),
            &CaptureConfig::default()
        ));
    }

    #[test]
    fn keeps_concealed_when_disabled() {
        let cfg = CaptureConfig {
            ignore_concealed: false,
            ..CaptureConfig::default()
        };
        assert!(should_store(&cap("secret", true, None), &cfg));
    }

    #[test]
    fn skips_excluded_app_case_insensitive() {
        let cfg = CaptureConfig {
            excluded_apps: vec!["com.apple.keychainaccess".to_string()],
            ..CaptureConfig::default()
        };
        assert!(!should_store(
            &cap("pw", false, Some("com.apple.KeychainAccess")),
            &cfg
        ));
        assert!(should_store(&cap("ok", false, Some("com.other.app")), &cfg));
    }
}

//! Portable fallback backend (used on non-macOS platforms for now).
//!
//! Uses [`arboard`] for plain-text read/write and a content hash for change
//! detection. Native Windows/Linux backends (clipboard sequence number,
//! concealed-format detection, active-window detection) replace this behind the
//! same [`ClipboardBackend`] trait.

use arboard::Clipboard;
use cliplex_core::{ClipAsset, ClipKind};

use crate::{Captured, ClipboardBackend, PlatformError, Result, UTI_TEXT};

/// Portable clipboard backend backed by `arboard`.
pub struct GenericBackend;

impl GenericBackend {
    pub fn new() -> Self {
        GenericBackend
    }

    fn clipboard() -> Result<Clipboard> {
        Clipboard::new().map_err(|e| PlatformError::Other(e.to_string()))
    }

    fn current_text() -> Option<String> {
        Clipboard::new().ok().and_then(|mut c| c.get_text().ok())
    }
}

impl ClipboardBackend for GenericBackend {
    fn change_token(&mut self) -> Result<u64> {
        // No portable change counter exists; hash the current text instead.
        let text = Self::current_text().unwrap_or_default();
        Ok(blake3_u64(text.as_bytes()))
    }

    fn read(&mut self) -> Result<Option<Captured>> {
        let Some(text) = Self::current_text() else {
            return Ok(None);
        };
        if text.is_empty() {
            return Ok(None);
        }
        Ok(Some(Captured {
            kind: ClipKind::Text,
            preview: text.clone(),
            concealed: false,
            source_app: None,
            assets: vec![ClipAsset {
                uti: UTI_TEXT.to_string(),
                bytes: text.into_bytes(),
                idx: 0,
            }],
        }))
    }

    fn write(&mut self, assets: &[ClipAsset]) -> Result<()> {
        if let Some(text) = assets.iter().find(|a| a.uti == UTI_TEXT) {
            let s = String::from_utf8_lossy(&text.bytes).to_string();
            let mut cb = Self::clipboard()?;
            cb.set_text(s)
                .map_err(|e| PlatformError::Other(e.to_string()))?;
            Ok(())
        } else {
            Err(PlatformError::Unsupported)
        }
    }

    fn active_app(&mut self) -> Result<Option<String>> {
        // Active-window detection is provided by the native backends.
        Ok(None)
    }
}

/// Folds a blake3 hash of `bytes` into a `u64` token.
fn blake3_u64(bytes: &[u8]) -> u64 {
    let hash = blake3::hash(bytes);
    let mut buf = [0u8; 8];
    buf.copy_from_slice(&hash.as_bytes()[..8]);
    u64::from_le_bytes(buf)
}

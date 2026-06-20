//! Native macOS clipboard backend using `NSPasteboard`.
//!
//! * Change detection uses the pasteboard `changeCount` (cheap, no polling of
//!   content).
//! * Reads plain text, RTF, and PNG/TIFF images, and flags concealed/secret
//!   clips via the `org.nspasteboard.*` type conventions.
//! * Active-app detection uses `NSWorkspace.frontmostApplication`.

use objc2::rc::Retained;
use objc2_app_kit::{
    NSPasteboard, NSPasteboardTypePNG, NSPasteboardTypeRTF, NSPasteboardTypeString,
    NSPasteboardTypeTIFF, NSWorkspace,
};
use objc2_foundation::{NSData, NSString};

use cliplex_core::{ClipAsset, ClipKind};

use crate::{
    Captured, ClipboardBackend, PlatformError, Result, CONCEALED_TYPES, UTI_PNG, UTI_TEXT,
};

const UTI_RTF: &str = "public.rtf";
const UTI_TIFF: &str = "public.tiff";

/// Native macOS clipboard backend.
pub struct MacBackend;

impl MacBackend {
    pub fn new() -> Self {
        MacBackend
    }

    fn pasteboard() -> Retained<NSPasteboard> {
        NSPasteboard::generalPasteboard()
    }

    /// Returns the list of pasteboard type identifiers currently present.
    fn type_strings(pb: &NSPasteboard) -> Vec<String> {
        let mut out = Vec::new();
        if let Some(types) = pb.types() {
            for t in types.iter() {
                out.push(t.to_string());
            }
        }
        out
    }

    fn data_for(pb: &NSPasteboard, ty: &NSString) -> Option<Vec<u8>> {
        let data: Retained<NSData> = pb.dataForType(ty)?;
        Some(data.to_vec())
    }
}

impl ClipboardBackend for MacBackend {
    fn change_token(&mut self) -> Result<u64> {
        let pb = Self::pasteboard();
        Ok(pb.changeCount() as u64)
    }

    fn read(&mut self) -> Result<Option<Captured>> {
        let pb = Self::pasteboard();
        let types = Self::type_strings(&pb);
        if types.is_empty() {
            return Ok(None);
        }
        let concealed = types
            .iter()
            .any(|t| CONCEALED_TYPES.iter().any(|c| c.eq_ignore_ascii_case(t)));

        let mut assets: Vec<ClipAsset> = Vec::new();
        let mut preview = String::new();
        let mut kind = ClipKind::Text;

        // Plain text (also used as the searchable preview).
        if let Some(s) = unsafe { pb.stringForType(NSPasteboardTypeString) } {
            let text = s.to_string();
            if !text.is_empty() {
                preview = text.clone();
                assets.push(ClipAsset {
                    uti: UTI_TEXT.to_string(),
                    bytes: text.into_bytes(),
                    idx: assets.len() as i64,
                });
            }
        }

        // Rich text (kept alongside the plain-text preview).
        if let Some(bytes) = Self::data_for(&pb, unsafe { NSPasteboardTypeRTF }) {
            if !bytes.is_empty() {
                if !preview.is_empty() {
                    kind = ClipKind::RichText;
                }
                assets.push(ClipAsset {
                    uti: UTI_RTF.to_string(),
                    bytes,
                    idx: assets.len() as i64,
                });
            }
        }

        // Images: prefer PNG, fall back to TIFF.
        if let Some(bytes) = Self::data_for(&pb, unsafe { NSPasteboardTypePNG }) {
            if !bytes.is_empty() {
                if preview.is_empty() {
                    kind = ClipKind::Image;
                    preview = "(Image)".to_string();
                }
                assets.push(ClipAsset {
                    uti: UTI_PNG.to_string(),
                    bytes,
                    idx: assets.len() as i64,
                });
            }
        } else if let Some(bytes) = Self::data_for(&pb, unsafe { NSPasteboardTypeTIFF }) {
            if !bytes.is_empty() {
                if preview.is_empty() {
                    kind = ClipKind::Image;
                    preview = "(Image)".to_string();
                }
                assets.push(ClipAsset {
                    uti: UTI_TIFF.to_string(),
                    bytes,
                    idx: assets.len() as i64,
                });
            }
        }

        if assets.is_empty() {
            return Ok(None);
        }

        Ok(Some(Captured {
            kind,
            preview,
            concealed,
            source_app: self.active_app().unwrap_or(None),
            assets,
        }))
    }

    fn write(&mut self, assets: &[ClipAsset]) -> Result<()> {
        let pb = Self::pasteboard();
        pb.clearContents();
        let mut wrote = false;
        for asset in assets {
            match asset.uti.as_str() {
                UTI_TEXT => {
                    let s = NSString::from_str(&String::from_utf8_lossy(&asset.bytes));
                    wrote |= unsafe { pb.setString_forType(&s, NSPasteboardTypeString) };
                }
                UTI_RTF => {
                    let data = NSData::with_bytes(&asset.bytes);
                    wrote |= unsafe { pb.setData_forType(Some(&data), NSPasteboardTypeRTF) };
                }
                UTI_PNG => {
                    let data = NSData::with_bytes(&asset.bytes);
                    wrote |= unsafe { pb.setData_forType(Some(&data), NSPasteboardTypePNG) };
                }
                UTI_TIFF => {
                    let data = NSData::with_bytes(&asset.bytes);
                    wrote |= unsafe { pb.setData_forType(Some(&data), NSPasteboardTypeTIFF) };
                }
                _ => {}
            }
        }
        if wrote {
            Ok(())
        } else {
            Err(PlatformError::Unsupported)
        }
    }

    fn active_app(&mut self) -> Result<Option<String>> {
        let ws = NSWorkspace::sharedWorkspace();
        let Some(app) = ws.frontmostApplication() else {
            return Ok(None);
        };
        let id = app
            .bundleIdentifier()
            .map(|s| s.to_string())
            .or_else(|| app.localizedName().map(|s| s.to_string()));
        Ok(id)
    }
}

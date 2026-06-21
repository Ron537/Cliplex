//! Native macOS window positioning.
//!
//! Places a window so its top-left corner sits at the mouse cursor, like a
//! native context menu. Using `NSWindow.setFrameTopLeftPoint` with
//! `NSEvent.mouseLocation` keeps everything in macOS's global *points*
//! coordinate space, so positioning is correct across displays with different
//! backing scale factors (e.g. a 2× Retina laptop next to a 1× external
//! monitor) — unlike a physical-pixel `set_position`, which the windowing layer
//! converts using the window's *current* scale factor.

use std::ffi::c_void;

use objc2::MainThreadMarker;
use objc2_app_kit::{NSEvent, NSScreen, NSWindow};
use objc2_foundation::{NSPoint, NSRect};

/// Positions the given `NSWindow` (raw pointer from `WebviewWindow::ns_window`)
/// so its top-left corner is at the mouse cursor, clamped to the visible area
/// of the screen under the cursor. Must be called on the main thread. Returns
/// `false` if positioning could not be performed (caller should fall back).
pub fn position_window_top_left_at_cursor(ns_window: *mut c_void) -> bool {
    if ns_window.is_null() {
        return false;
    }
    let Some(mtm) = MainThreadMarker::new() else {
        return false;
    };

    // SAFETY: the pointer is a valid NSWindow for the lifetime of this call.
    let window: &NSWindow = unsafe { &*(ns_window as *const NSWindow) };

    let mouse: NSPoint = NSEvent::mouseLocation();
    let size = window.frame().size;
    let (w, h) = (size.width, size.height);

    let visible = screen_visible_frame_at(mtm, mouse);
    let Some(vf) = visible else {
        return false;
    };

    let margin = 6.0;
    let mut x = mouse.x;
    let mut top_y = mouse.y;

    // Clamp horizontally so the whole window stays on-screen.
    let min_x = vf.origin.x + margin;
    let max_x = vf.origin.x + vf.size.width - w - margin;
    if max_x >= min_x {
        x = x.clamp(min_x, max_x);
    } else {
        x = min_x;
    }

    // top_y is the top edge (bottom = top_y - h), bottom-left origin.
    let min_top = vf.origin.y + h + margin;
    let max_top = vf.origin.y + vf.size.height - margin;
    if max_top >= min_top {
        top_y = top_y.clamp(min_top, max_top);
    } else {
        top_y = max_top;
    }

    window.setFrameTopLeftPoint(NSPoint::new(x, top_y));
    true
}

/// Returns the `visibleFrame` of the screen containing `point`, falling back to
/// the main screen.
fn screen_visible_frame_at(mtm: MainThreadMarker, point: NSPoint) -> Option<NSRect> {
    let screens = NSScreen::screens(mtm);
    for screen in screens.iter() {
        let f = screen.frame();
        if point.x >= f.origin.x
            && point.x <= f.origin.x + f.size.width
            && point.y >= f.origin.y
            && point.y <= f.origin.y + f.size.height
        {
            return Some(screen.visibleFrame());
        }
    }
    NSScreen::mainScreen(mtm).map(|s| s.visibleFrame())
}

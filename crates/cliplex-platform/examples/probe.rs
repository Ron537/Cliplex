//! Read-only runtime probe for the platform backend.
//!
//! Prints the current clipboard change token, the frontmost app, and a short
//! preview of the current clipboard contents. Does not modify the clipboard.
//!
//! Run with: `cargo run -p cliplex-platform --example probe`

fn main() {
    let mut backend = cliplex_platform::backend();

    match backend.change_token() {
        Ok(token) => println!("change_token: {token}"),
        Err(e) => println!("change_token error: {e}"),
    }

    match backend.active_app() {
        Ok(app) => println!("active_app: {app:?}"),
        Err(e) => println!("active_app error: {e}"),
    }

    match backend.read() {
        Ok(Some(c)) => {
            let preview: String = c.preview.chars().take(60).collect();
            println!(
                "read: kind={:?} concealed={} source_app={:?} assets={} preview={:?}",
                c.kind,
                c.concealed,
                c.source_app,
                c.assets.len(),
                preview
            );
        }
        Ok(None) => println!("read: <empty clipboard>"),
        Err(e) => println!("read error: {e}"),
    }
}

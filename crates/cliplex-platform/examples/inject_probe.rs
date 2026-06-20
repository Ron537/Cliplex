//! Probe to confirm paste injection works on the main thread.
//!
//! `cargo run -p cliplex-platform --example inject_probe`          (main thread)
//! `cargo run -p cliplex-platform --example inject_probe -- bg`    (background thread)
//!
//! On macOS the background variant is expected to abort (Text Input Source APIs
//! assert main-thread affinity); the main-thread variant should succeed.

fn main() {
    let bg = std::env::args().nth(1).as_deref() == Some("bg");
    if bg {
        std::thread::spawn(|| {
            println!("bg inject: {:?}", cliplex_platform::inject_paste());
        })
        .join()
        .unwrap();
    } else {
        println!("main inject: {:?}", cliplex_platform::inject_paste());
    }
}

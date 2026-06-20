//! Reports whether the current process is trusted for Accessibility.
//!
//! `cargo run -p cliplex-platform --example ax_probe`
//! Pass `--prompt` to also trigger the system permission prompt.

fn main() {
    println!("is_trusted: {}", cliplex_platform::is_trusted());
    if std::env::args().any(|a| a == "--prompt") {
        println!("requesting trust (system prompt may appear)…");
        cliplex_platform::prompt_for_trust();
        println!(
            "is_trusted after prompt call: {}",
            cliplex_platform::is_trusted()
        );
    }
}

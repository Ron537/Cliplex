//! Probe for frontmost-app capture + re-activation.
//!
//! `cargo run -p cliplex-platform --example focus_probe`
//!
//! Captures the current frontmost app pid, prints it, waits 2s (switch to a
//! different app), then re-activates the captured one.

fn main() {
    let pid = cliplex_platform::frontmost_pid();
    println!("frontmost pid: {pid:?}");
    if let Some(pid) = pid {
        println!("switch to another app now… reactivating in 2s");
        std::thread::sleep(std::time::Duration::from_secs(2));
        let ok = cliplex_platform::activate_pid(pid);
        println!("activate_pid({pid}) -> {ok}");
    }
}

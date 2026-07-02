import Foundation

/// Background clipboard monitor.
///
/// Polls the pasteboard `changeCount` on a configurable interval; when the
/// clipboard changes it reads the content, applies the capture filter (privacy
/// by default), stores it, prunes overflow, and invokes `onChange`.
///
/// Polling runs on the main run loop in `.common` mode: the `changeCount` check
/// is trivially cheap, and reading `NSPasteboard` on the main thread avoids the
/// thread-safety caveats of off-main pasteboard access.
public final class ClipboardMonitor {
    private let store: ClipStore
    private let clipboard: MacClipboard
    private let settingsProvider: () -> AppSettings
    private let onChange: () -> Void

    private var timer: Timer?
    private var lastToken: Int?
    private var intervalMs: Int = 0

    public init(
        store: ClipStore,
        clipboard: MacClipboard = MacClipboard(),
        settingsProvider: @escaping () -> AppSettings,
        onChange: @escaping () -> Void
    ) {
        self.store = store
        self.clipboard = clipboard
        self.settingsProvider = settingsProvider
        self.onChange = onChange
    }

    /// Whether polling is currently active.
    public var isRunning: Bool { timer != nil }

    /// Starts polling. On a normal start the current clipboard is captured on the
    /// first tick. Pass `capturingCurrent: false` when *resuming* after a pause so
    /// whatever is already on the pasteboard (possibly copied while paused) is not
    /// captured — only subsequent changes are.
    public func start(capturingCurrent: Bool = true) {
        if !capturingCurrent { lastToken = clipboard.changeToken }
        scheduleTimer(intervalMs: settingsProvider().pollIntervalMs)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTimer(intervalMs: Int) {
        timer?.invalidate()
        self.intervalMs = intervalMs
        let timer = Timer(timeInterval: Double(intervalMs) / 1000.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let settings = settingsProvider()
        // Adapt to a changed poll interval, mirroring the previous build which
        // re-read the interval every loop.
        if settings.pollIntervalMs != intervalMs {
            scheduleTimer(intervalMs: settings.pollIntervalMs)
        }

        let token = clipboard.changeToken
        if token == lastToken { return }
        lastToken = token

        guard let captured = clipboard.read() else { return }
        guard shouldStore(captured, config: settings.captureConfig) else { return }

        do {
            try store.addClip(captured.toNewClip())
            try store.pruneClips(maxItems: settings.maxHistory)
            onChange()
        } catch {
            // Storage failures are non-fatal; the next change will retry.
        }
    }
}

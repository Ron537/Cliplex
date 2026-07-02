import SwiftUI
import CliplexKit
import KeyboardShortcuts

/// The Settings window (design "A" — System-Settings-style): a category sidebar
/// with icon tiles and a grouped detail pane. Binds to ``ManagerViewModel``.
struct SettingsView: View {
    @ObservedObject var viewModel: ManagerViewModel
    @State private var category: Category = .general

    enum Category: String, CaseIterable, Identifiable {
        case general, history, shortcuts, appearance, privacy
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .history: return "clock.arrow.circlepath"
            case .shortcuts: return "keyboard"
            case .appearance: return "circle.lefthalf.filled"
            case .privacy: return "lock.shield"
            }
        }
    }

    /// The app's marketing version, read from the bundle so it never drifts.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            brandBar
            Divider().overlay(Theme.hairline)
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Theme.hairline).frame(width: 1)
                ScrollView { pane.padding(26).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 540)
        .background(WindowBackground())
        .tint(Theme.accent)
        .onChange(of: viewModel.settings) { viewModel.applySettings() }
        .onChange(of: viewModel.autostartEnabled) { viewModel.applyAutostart() }
    }

    /// The integrated titlebar brand row (sits just below the traffic lights).
    private var brandBar: some View {
        HStack(spacing: 9) {
            BrandMark(size: 24)
            Text("Cliplex").font(.display(15, .bold))
            Text("Settings").font(.ui(13, .medium)).foregroundStyle(Theme.mutedText)
            Spacer()
        }
        .padding(.leading, 20).padding(.trailing, 14).frame(height: 46)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Category.allCases) { cat in
                navItem(cat)
            }
            Spacer()
            Text("Cliplex \(Self.appVersion) · No telemetry")
                .font(.ui(11)).foregroundStyle(Theme.mutedText)
                .padding(.horizontal, 10).padding(.bottom, 4)
        }
        .padding(10)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.railBackground)
    }

    private func navItem(_ cat: Category) -> some View {
        let on = category == cat
        return Button { category = cat } label: {
            HStack(spacing: 11) {
                Image(systemName: cat.icon).font(.ui(12))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(on ? Theme.accentInk : Theme.secondaryText)
                    .background(on ? Theme.accent : Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
                Text(cat.title).font(.ui(13, .semibold))
                    .foregroundStyle(on ? Theme.primaryText : Theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(on ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: - Pane

    @ViewBuilder
    private var pane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.title).font(.display(24, .bold))
            Text(subtitle).font(.ui(13)).foregroundStyle(Theme.mutedText)
                .padding(.top, 3).padding(.bottom, 22)
            switch category {
            case .general: generalGroup
            case .history: historyGroup
            case .shortcuts: shortcutsGroup
            case .appearance: appearanceGroup
            case .privacy: privacyGroup
            }
        }
    }

    private var subtitle: String {
        switch category {
        case .general: return "How Cliplex behaves day to day."
        case .history: return "Control how much clipboard history Cliplex keeps."
        case .shortcuts: return "Global hotkeys to summon Cliplex from anywhere."
        case .appearance: return "Match Cliplex to your system or pick a side."
        case .privacy: return "Cliplex is local-first. Nothing leaves your Mac."
        }
    }

    // MARK: - Groups

    private var generalGroup: some View {
        SettingsCard {
            SettingsRow(icon: "arrow.down.to.line", title: "Launch at login",
                        desc: "Start Cliplex automatically and keep it in the menu bar.") {
                SettingsToggle(isOn: $viewModel.autostartEnabled)
            }
            RowDivider()
            SettingsRow(icon: "doc.on.clipboard", title: "Paste automatically on select",
                        desc: "Pressing Return pastes into the frontmost app instead of just copying.") {
                SettingsToggle(isOn: $viewModel.settings.pasteOnSelect)
            }
        }
    }

    private var historyGroup: some View {
        SettingsCard {
            SettingsRow(icon: "tray.full", title: "Maximum history",
                        desc: "Older unpinned clips are pruned automatically.") {
                HistoryStepper(value: $viewModel.settings.maxHistory)
            }
            RowDivider()
            SettingsRow(icon: "trash", iconColor: Color(nsColor: NSColor(hex: 0xFF5A5A)),
                        title: "Clear history now", desc: "Remove all unpinned clips immediately.") {
                Button("Clear") { viewModel.clearHistory() }
                    .buttonStyle(.plain)
                    .font(.ui(12.5, .semibold))
                    .foregroundStyle(Color(nsColor: NSColor(hex: 0xFF5A5A)))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
            }
        }
    }

    private var shortcutsGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(icon: "doc.on.clipboard", title: "Open Cliplex", desc: "Clipboard history at the cursor.") {
                    KeyboardShortcuts.Recorder(for: .openCliplex)
                }
                RowDivider()
                SettingsRow(icon: "text.alignleft", iconColor: Theme.snippetAccent, title: "Open Snippets",
                            desc: "Jump straight to the Snippets tab.") {
                    KeyboardShortcuts.Recorder(for: .openSnippets)
                }
                RowDivider()
                SettingsRow(icon: "bolt.fill", iconColor: Theme.actionAccent, title: "Open Actions",
                            desc: "Jump straight to the Actions tab.") {
                    KeyboardShortcuts.Recorder(for: .openActions)
                }
            }
            InfoCallout(icon: "info.circle",
                        text: "Per-folder and per-item shortcuts live in the Library — open any folder, snippet, or action and click its shortcut chip.")
        }
    }

    private var appearanceGroup: some View {
        SettingsCard {
            SettingsRow(icon: "circle.lefthalf.filled", title: "Theme", desc: "System follows macOS automatically.") {
                Picker("", selection: $viewModel.settings.theme) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            RowDivider()
            SettingsRow(icon: "rectangle.compress.vertical", title: "Compact panel rows",
                        desc: "Single-line rows with a smaller icon in the ⌘⇧V panel.") {
                SettingsToggle(isOn: $viewModel.settings.compactPanel)
            }
        }
    }

    private var privacyGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(icon: "lock.shield", title: "Ignore concealed & password clips",
                            desc: "Skip anything copied from password managers.") {
                    SettingsToggle(isOn: $viewModel.settings.ignoreConcealed)
                }
                SettingsRow(icon: "trash", title: "Clear history on quit",
                            desc: "Wipe unpinned history when you quit Cliplex. Pinned clips stay.") {
                    SettingsToggle(isOn: $viewModel.settings.clearHistoryOnQuit)
                }
            }
            InfoCallout(icon: "checkmark.shield", tint: Theme.snippetAccent,
                        text: "No telemetry, no accounts, no cloud. History and snippets are stored in a local SQLite database you fully own.")
        }
    }
}

// MARK: - Building blocks

/// A grouped settings card (rounded container with hairline-separated rows).
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.elevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline, lineWidth: 1))
            .frame(maxWidth: 540, alignment: .leading)
    }
}

/// A single settings row: icon tile + title/description + trailing control. Rows
/// draw a divider above all but the first via the enclosing card layout.
struct SettingsRow<Control: View>: View {
    let icon: String
    var iconColor: Color = Theme.secondaryText
    let title: String
    let desc: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.ui(14))
                .frame(width: 30, height: 30).foregroundStyle(iconColor)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13.5, .semibold)).foregroundStyle(Theme.primaryText)
                Text(desc).font(.ui(11.5)).foregroundStyle(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }
}

/// A hairline divider between rows inside a ``SettingsCard``.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 15) }
}

/// The pill toggle used in settings.
struct SettingsToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 20)
                .fill(isOn ? Theme.accent : Theme.hairline)
                .frame(width: 40, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
        }.buttonStyle(.plain)
    }
}

/// The numeric stepper for "Maximum history".
struct HistoryStepper: View {
    @Binding var value: Int64
    var body: some View {
        HStack(spacing: 0) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.ui(13, .semibold)).frame(width: 56)
            VStack(spacing: 0) {
                stepButton("chevron.up") { value = min(100_000, value + 50) }
                stepButton("chevron.down") { value = max(10, value - 50) }
            }
        }
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.hairline, lineWidth: 1))
    }
    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.ui(8, .bold)).foregroundStyle(Theme.secondaryText)
                .frame(width: 24, height: 15)
        }.buttonStyle(.plain)
    }
}

/// An informational callout used in Shortcuts/Privacy.
struct InfoCallout: View {
    let icon: String
    var tint: Color = Theme.accent
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).font(.ui(14)).foregroundStyle(tint)
            Text(text).font(.ui(11.5)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: 540, alignment: .leading)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(tint.opacity(0.28), lineWidth: 1))
    }
}

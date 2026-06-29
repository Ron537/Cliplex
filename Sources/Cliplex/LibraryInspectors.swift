import SwiftUI
import CliplexKit

// MARK: - Snippet inspector

/// The adaptive inspector for a snippet (right pane of the Library Workbench).
struct SnippetInspector: View {
    @ObservedObject var snippets: ManagerViewModel
    let folders: [SnippetFolder]

    private var saved: Bool { !snippets.isDraft && snippets.selectedSnippetID != nil }

    private var folderName: String {
        guard saved, let fid = snippets.editingSnippetFolderID else { return snippets.selectedFolderName }
        return folders.first { $0.id == fid }?.name ?? "Uncategorized"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    InspectorField("Title") {
                        TextField("Title", text: $snippets.draftTitle)
                            .textFieldStyle(.plain).font(.ui(14, .medium))
                            .inspectorInput()
                    }
                    InspectorField("Content", hint: "paste-ready") {
                        TextEditor(text: $snippets.draftContent)
                            .font(.mono(12.5))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .padding(8)
                            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
                        if snippets.draftContent.contains("{clipboard}") { ClipboardTokenChip() }
                    }
                    folderField
                    if saved, let id = snippets.selectedSnippetID {
                        shortcutField(id: id)
                    }
                    callout
                }
                .padding(18)
            }
            Divider().overlay(Theme.hairline)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "text.alignleft").font(.ui(17))
                .frame(width: 40, height: 40).foregroundStyle(Theme.snippetAccent)
                .background(Theme.snippetAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("Snippet · \(folderName)".uppercased())
                    .font(.ui(10.5, .bold)).tracking(0.4).foregroundStyle(Theme.mutedText)
                Text(snippets.draftTitle.isEmpty ? "Untitled" : snippets.draftTitle)
                    .font(.display(17, .bold)).lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var folderField: some View {
        if saved {
            InspectorField("Folder") {
                Picker("", selection: Binding(
                    get: { snippets.editingSnippetFolderID },
                    set: { snippets.moveEditingSnippet(to: $0) }
                )) {
                    Text("Uncategorized").tag(Int64?.none)
                    ForEach(folders) { f in Text(f.name).tag(Int64?.some(f.id)) }
                }
                .labelsHidden().pickerStyle(.menu).inspectorInput()
            }
        } else {
            Text("Saving to  ▸ \(snippets.selectedFolderName)")
                .font(.ui(11.5)).foregroundStyle(Theme.mutedText)
        }
    }

    private func shortcutField(id: Int64) -> some View {
        InspectorField("Quick-paste shortcut") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Paste this snippet instantly").font(.ui(12.5, .medium))
                    Text("Works anywhere, even when Cliplex is closed")
                        .font(.ui(11)).foregroundStyle(Theme.mutedText)
                }
                Spacer()
                ShortcutChip(kind: .snippet, id: id, large: true)
            }
            .padding(11)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle").font(.ui(13)).foregroundStyle(Theme.accent)
            (Text("Use ") + Text("{clipboard}").font(.mono(11.5)).foregroundColor(Theme.accent)
                + Text(" inside a snippet to weave in whatever you copied last."))
                .font(.ui(11.5)).foregroundStyle(Theme.secondaryText)
        }
        .padding(11)
        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if saved {
                GhostButton(title: "Duplicate") { snippets.duplicateEditingSnippet() }
                Button { snippets.requestDeleteEditingSnippet() } label: {
                    Image(systemName: "trash").font(.ui(12, .semibold))
                        .foregroundStyle(Color(nsColor: NSColor(hex: 0xFF5A5A)))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            if snippets.isDraft {
                GhostButton(title: "Discard", danger: true) { snippets.discardDraft() }.keyboardShortcut(.cancelAction)
            }
            Spacer()
            PrimaryButton(title: "Save changes") { snippets.saveSnippet() }.keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
    }
}

// MARK: - Action inspector

struct ActionInspector: View {
    @ObservedObject var actions: ActionsViewModel
    let folders: [ActionFolder]

    private var saved: Bool { !actions.isDraft && actions.selectedActionID != nil }

    private var folderName: String {
        guard saved, let fid = actions.editingActionFolderID else { return actions.selectedFolderName }
        return folders.first { $0.id == fid }?.name ?? "Uncategorized"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    InspectorField("Title") {
                        TextField("Title", text: $actions.draftTitle)
                            .textFieldStyle(.plain).font(.ui(14, .medium)).inspectorInput()
                    }
                    InspectorField("Type") {
                        Picker("", selection: $actions.draftType) {
                            ForEach(ActionType.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden().pickerStyle(.menu).inspectorInput()
                    }
                    if actions.draftUsesValue {
                        InspectorField(valueLabel, hint: "{clipboard}") {
                            TextField(valuePlaceholder, text: $actions.draftValue)
                                .textFieldStyle(.plain).font(.mono(13)).inspectorInput()
                            if actions.draftValue.contains("{clipboard}") { ClipboardTokenChip() }
                            Text(valueHint).font(.ui(11)).foregroundStyle(Theme.mutedText)
                        }
                    } else {
                        InspectorField("Transform") {
                            Picker("", selection: $actions.draftTransform) {
                                ForEach(ActionTransform.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden().pickerStyle(.menu).inspectorInput()
                            Text("Applies to the current clipboard text and writes the result back.")
                                .font(.ui(11)).foregroundStyle(Theme.mutedText)
                        }
                    }
                    folderField
                    if saved, let id = actions.selectedActionID { shortcutField(id: id) }
                }
                .padding(18)
            }
            Divider().overlay(Theme.hairline)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: actions.draftType.symbol).font(.ui(17))
                .frame(width: 40, height: 40).foregroundStyle(Theme.actionAccent)
                .background(Theme.actionAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("Action · \(folderName)".uppercased())
                    .font(.ui(10.5, .bold)).tracking(0.4).foregroundStyle(Theme.mutedText)
                Text(actions.draftTitle.isEmpty ? "Untitled" : actions.draftTitle)
                    .font(.display(17, .bold)).lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var folderField: some View {
        if saved {
            InspectorField("Folder") {
                Picker("", selection: Binding(
                    get: { actions.editingActionFolderID },
                    set: { actions.moveEditingAction(to: $0) }
                )) {
                    Text("Uncategorized").tag(Int64?.none)
                    ForEach(folders) { f in Text(f.name).tag(Int64?.some(f.id)) }
                }.labelsHidden().pickerStyle(.menu).inspectorInput()
            }
        } else {
            Text("Saving to  ▸ \(actions.selectedFolderName)")
                .font(.ui(11.5)).foregroundStyle(Theme.mutedText)
        }
    }

    private func shortcutField(id: Int64) -> some View {
        InspectorField("Run shortcut") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trigger this action anywhere").font(.ui(12.5, .medium))
                    Text("Global hotkey, no window needed").font(.ui(11)).foregroundStyle(Theme.mutedText)
                }
                Spacer()
                ShortcutChip(kind: .action, id: id, large: true)
            }
            .padding(11)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if saved {
                GhostButton(title: "Duplicate") { actions.duplicateEditingAction() }
                Button { actions.requestDeleteEditingAction() } label: {
                    Image(systemName: "trash").font(.ui(12, .semibold))
                        .foregroundStyle(Color(nsColor: NSColor(hex: 0xFF5A5A)))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            if actions.isDraft {
                GhostButton(title: "Discard", danger: true) { actions.discardDraft() }.keyboardShortcut(.cancelAction)
            }
            Spacer()
            PrimaryButton(title: "Save changes") { actions.save() }.keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
    }

    private var valueLabel: String {
        switch actions.draftType {
        case .openURL: return "URL"
        case .openApp: return "Application"
        case .openPath: return "File or Folder Path"
        case .transform: return "Value"
        }
    }
    private var valuePlaceholder: String {
        switch actions.draftType {
        case .openURL: return "https://github.com/search?q={clipboard}"
        case .openApp: return "com.apple.Safari  or  /Applications/Safari.app"
        case .openPath: return "~/Projects/my-repo"
        case .transform: return ""
        }
    }
    private var valueHint: String {
        switch actions.draftType {
        case .openURL: return "Use {clipboard} to insert the current clipboard text (URL-encoded)."
        case .openApp: return "A bundle identifier or an app path. {clipboard} is supported."
        case .openPath: return "Opens in Finder / the default app. {clipboard} and ~ are supported."
        case .transform: return ""
        }
    }
}

// MARK: - Shared field

/// A noticeable accent pill shown when a field contains the {clipboard} token.
struct ClipboardTokenChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.ui(10))
            Text("{clipboard}").font(.mono(11, .semibold))
            Text("→ your current clipboard").font(.ui(10.5))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1))
    }
}

/// A labelled inspector field (uppercase caption + content).
struct InspectorField<Content: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder var content: Content

    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.hint = hint; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(title).font(.ui(11.5, .bold)).foregroundStyle(Theme.secondaryText)
                if let hint {
                    Spacer()
                    Text(hint).font(.mono(10.5)).foregroundStyle(Theme.mutedText)
                }
            }
            content
        }
    }
}

extension View {
    /// The shared rounded inset look for inspector text fields / pickers.
    func inspectorInput() -> some View {
        self.padding(.horizontal, 11).padding(.vertical, 9)
            .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

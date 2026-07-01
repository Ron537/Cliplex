import SwiftUI
import CliplexKit

/// The unified Library window (design "A" — the Workbench): a combined folder
/// rail for snippets *and* actions, an item list, and an adaptive inspector.
/// Every folder and item carries an assignable global shortcut.
struct LibraryView: View {
    @ObservedObject var library: LibraryViewModel
    @ObservedObject var snippets: ManagerViewModel
    @ObservedObject var actions: ActionsViewModel

    @State private var railWidth: CGFloat = 256
    @State private var inspectorWidth: CGFloat = 344
    @State private var hoveredFolder: String?
    @State private var hoveredItem: String?
    @FocusState private var searchFocused: Bool
    @State private var showNew = false

    private let railRange: ClosedRange<CGFloat> = 224...320
    private let inspectorRange: ClosedRange<CGFloat> = 300...460
    private let listMin: CGFloat = 280

    init(library: LibraryViewModel) {
        self.library = library
        self.snippets = library.snippets
        self.actions = library.actions
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.hairline)
            GeometryReader { geo in
                let widths = paneWidths(container: geo.size.width)
                HStack(spacing: 0) {
                    rail.frame(width: widths.rail)
                    PaneResizer(width: $railWidth,
                                minWidth: railRange.lowerBound,
                                maxWidth: min(railRange.upperBound, geo.size.width - widths.inspector - listMin - 2))
                    itemList.frame(maxWidth: .infinity)
                    PaneResizer(width: $inspectorWidth,
                                minWidth: inspectorRange.lowerBound,
                                maxWidth: min(inspectorRange.upperBound, geo.size.width - widths.rail - listMin - 2))
                    inspector.frame(width: widths.inspector)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .tint(Theme.accent)
        .background(WindowBackground())
        .overlay { dialogs }
    }

    private func paneWidths(container: CGFloat) -> (rail: CGFloat, inspector: CGFloat) {
        let available = max(0, container - 2)
        var rail = railWidth.clamped(to: railRange)
        var inspector = inspectorWidth.clamped(to: inspectorRange)
        let maxSides = max(0, available - listMin)
        if rail + inspector > maxSides {
            inspector = max(inspectorRange.lowerBound, maxSides - rail)
            if rail + inspector > maxSides {
                rail = max(railRange.lowerBound, maxSides - inspector)
            }
        }
        return (rail, inspector)
    }

    // MARK: - Toolbar (two rows; the first shares the window's titlebar)

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                brand
                Spacer(minLength: 12)
                searchField
                newMenu
            }
            .padding(.leading, 20).padding(.trailing, 14).frame(height: 46)

            HStack(spacing: 12) {
                FilterSegmented(selection: $library.filter)
                Spacer(minLength: 8)
                Text("\(library.folderCount) folders · \(library.itemCount) items")
                    .font(.ui(12, .medium)).foregroundStyle(Theme.mutedText)
                ioMenu
            }
            .padding(.horizontal, 14).frame(height: 42)
        }
        .background {
            // Invisible buttons that back the New menu's ⌘N / ⌘⇧N labels.
            Group {
                Button("") { library.newSnippet() }.keyboardShortcut("n", modifiers: .command)
                Button("") { library.newAction() }.keyboardShortcut("n", modifiers: [.command, .shift])
            }.opacity(0)
        }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            BrandMark(size: 24)
            Text("Cliplex").font(.display(15, .bold))
            Text("Library").font(.ui(13, .medium)).foregroundStyle(Theme.mutedText)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.ui(12)).foregroundStyle(Theme.mutedText)
            TextField("Search snippets & actions", text: $library.query)
                .textFieldStyle(.plain)
                .font(.ui(13))
                .focused($searchFocused)
            if library.query.isEmpty {
                HStack(spacing: 1) { Text("⌘").font(.mono(10.5)); Text("F").font(.mono(10.5)) }
                    .foregroundStyle(Theme.mutedText)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline, lineWidth: 0.5))
            } else {
                Button { library.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.ui(12)).foregroundStyle(Theme.mutedText)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).frame(width: 248, height: 30)
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(searchFocused ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1))
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0)
        }
    }

    private var newMenu: some View {
        Button { showNew.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.ui(12, .bold))
                Text("New").font(.ui(13, .semibold))
                Image(systemName: "chevron.down").font(.ui(9, .bold))
            }
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).fixedSize()
        .popover(isPresented: $showNew, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                newMenuRow("New Snippet", "text.alignleft", Theme.snippetAccent, "⌘N") { library.newSnippet() }
                newMenuRow("New Action", "bolt.fill", Theme.actionAccent, "⌘⇧N") { library.newAction() }
                Divider().overlay(Theme.hairline).padding(.vertical, 4)
                newMenuRow("New Snippet Folder", "folder.badge.plus", Theme.snippetAccent, nil) { library.newSnippetFolder() }
                newMenuRow("New Action Folder", "folder.badge.plus", Theme.actionAccent, nil) { library.newActionFolder() }
            }
            .padding(6)
            .frame(width: 220)
        }
    }

    private func newMenuRow(_ title: String, _ icon: String, _ color: Color, _ kbd: String?, action: @escaping () -> Void) -> some View {
        NewMenuRow(title: title, icon: icon, color: color, kbd: kbd) { showNew = false; action() }
    }

    private var ioMenu: some View {
        Menu {
            Button("Import Snippets…") { snippets.importSnippets() }
            Button("Export Snippets…") { snippets.exportSnippets() }
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.ui(12, .semibold)).foregroundStyle(Theme.secondaryText)
                .frame(width: 28, height: 26)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Import / Export")
    }

    // MARK: - Rail

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if library.showsSnippets {
                    groupHeader("Snippets", color: Theme.snippetAccent) { library.newSnippetFolder() }
                    folderRow(domain: .snippet, folder: nil, name: "All snippets", icon: "tray.full", count: snippets.totalSnippetCount)
                    ForEach(snippets.folders) { folder in
                        folderRow(domain: .snippet, folder: folder, name: folder.name, icon: "folder",
                                  count: snippets.count(inFolder: folder.id))
                    }
                }
                if library.showsActions {
                    groupHeader("Actions", color: Theme.actionAccent) { library.newActionFolder() }
                        .padding(.top, library.showsSnippets ? 8 : 0)
                    folderRow(domain: .action, folder: nil, name: "All actions", icon: "bolt.fill", count: actions.totalActionCount)
                    ForEach(actions.folders) { folder in
                        folderRow(domain: .action, folder: folder, name: folder.name, icon: "folder",
                                  count: actions.count(inFolder: folder.id))
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.railBackground)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private func groupHeader(_ title: String, color: Color, add: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title.uppercased())
                .font(.ui(10.5, .bold)).tracking(0.9)
                .foregroundStyle(Theme.mutedText)
            Spacer()
            Button(action: add) {
                Image(systemName: "plus").font(.ui(11, .bold)).foregroundStyle(Theme.mutedText)
                    .frame(width: 18, height: 18)
            }.buttonStyle(.plain).help("New folder")
        }
        .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 6)
    }

    @ViewBuilder
    private func folderRow(domain: LibraryViewModel.Domain, folder: AnyFolder?, name: String, icon: String, count: Int) -> some View {
        let isSnippet = domain == .snippet
        let id = folder?.id
        let key = "\(isSnippet ? "s" : "a")-\(id.map(String.init) ?? "all")"
        let selected = isSnippet ? library.isSnippetFolderSelected(id) : library.isActionFolderSelected(id)
        let hovered = hoveredFolder == key
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.ui(12)).frame(width: 16)
                .foregroundStyle(selected ? Theme.accent : Theme.mutedText)
            Text(name).font(.ui(13, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.primaryText : Theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let id {
                ShortcutChip(kind: isSnippet ? .snippetFolder : .actionFolder, id: id)
                    .opacity(hasShortcut(isSnippet ? .snippetFolder : .actionFolder, id) || hovered || selected ? 1 : 0)
            }
            Text("\(count)")
                .font(.ui(11, .medium)).foregroundStyle(Theme.mutedText)
                .frame(minWidth: 16, alignment: .trailing)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(selected ? Theme.accent.opacity(0.14) : (hovered ? Theme.fieldBackground : .clear),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Theme.accent.opacity(0.28) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hoveredFolder = $0 ? key : (hoveredFolder == key ? nil : hoveredFolder) }
        .onTapGesture { isSnippet ? library.selectSnippetFolder(id) : library.selectActionFolder(id) }
        .contextMenu {
            if let folder {
                Button("Rename…") {
                    isSnippet ? snippets.requestRenameFolder(folder.snippet!) : actions.requestRenameFolder(folder.action!)
                }
                Button("Delete…", role: .destructive) {
                    isSnippet ? snippets.requestDeleteFolder(folder.snippet!) : actions.requestDeleteFolder(folder.action!)
                }
            }
        }
    }

    private func hasShortcut(_ kind: ShortcutCenter.Kind, _ id: Int64) -> Bool {
        ShortcutCenter.shared.hasShortcut(kind, id)
    }

    // MARK: - Item list

    private var itemList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(library.listTitle).font(.display(16, .bold)).lineLimit(1)
                Text(library.listIsSnippets ? "Snippet folder" : "Action folder")
                    .font(.ui(9.5, .bold)).tracking(0.4)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background((library.listIsSnippets ? Theme.snippetAccent : Theme.actionAccent).opacity(0.16),
                               in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(library.listIsSnippets ? Theme.snippetAccent : Theme.actionAccent)
                Spacer()
                Text("\(library.listCount) items").font(.ui(12)).foregroundStyle(Theme.mutedText)
            }
            .padding(.horizontal, 14).frame(height: 44)
            Divider().overlay(Theme.hairline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if library.listIsSnippets {
                        if snippets.isDraft { snippetDraftRow }
                        ForEach(library.visibleSnippets) { snippetRow($0) }
                        if library.visibleSnippets.isEmpty && !snippets.isDraft { emptyList("No snippets here") }
                    } else {
                        if actions.isDraft { actionDraftRow }
                        ForEach(library.visibleActions) { actionRow($0) }
                        if library.visibleActions.isEmpty && !actions.isDraft { emptyList("No actions here") }
                    }
                }
                .padding(8)
            }
        }
    }

    private func emptyList(_ text: String) -> some View {
        Text(text).font(.ui(13)).foregroundStyle(Theme.mutedText)
            .frame(maxWidth: .infinity).padding(.top, 40)
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        let selected = !snippets.isDraft && snippets.selectedSnippetID == snippet.id && library.activeDomain == .snippet
        let key = "s-\(snippet.id)"
        return itemRowShell(
            selected: selected, hoverKey: key, accent: Theme.snippetAccent, icon: "text.alignleft",
            title: snippet.title.isEmpty ? "Untitled" : snippet.title,
            subtitle: snippet.content.replacingOccurrences(of: "\n", with: " ").prefix(80).description,
            chip: { ShortcutChip(kind: .snippet, id: snippet.id) },
            chipVisible: hasShortcut(.snippet, snippet.id),
            onDelete: { snippets.requestDeleteSnippet(snippet) },
            onTap: { library.activeDomainSelectSnippet(snippet) }
        )
    }

    private func actionRow(_ action: ActionItem) -> some View {
        let selected = !actions.isDraft && actions.selectedActionID == action.id && library.activeDomain == .action
        let key = "a-\(action.id)"
        return itemRowShell(
            selected: selected, hoverKey: key, accent: Theme.actionAccent, icon: action.type.symbol,
            title: action.title.isEmpty ? "Untitled" : action.title,
            subtitle: actionSubtitle(action),
            chip: { ShortcutChip(kind: .action, id: action.id) },
            chipVisible: hasShortcut(.action, action.id),
            onDelete: { actions.requestDeleteAction(action) },
            onTap: { library.activeDomainSelectAction(action) }
        )
    }

    private func actionSubtitle(_ action: ActionItem) -> String {
        switch action.type {
        case .transform: return action.transform?.label ?? "Transform"
        default: return action.value.isEmpty ? action.type.label : action.value
        }
    }

    @ViewBuilder
    private func itemRowShell<Chip: View>(
        selected: Bool, hoverKey: String, accent: Color, icon: String,
        title: String, subtitle: String, @ViewBuilder chip: () -> Chip, chipVisible: Bool,
        onDelete: @escaping () -> Void, onTap: @escaping () -> Void
    ) -> some View {
        let hovered = hoveredItem == hoverKey
        HStack(spacing: 11) {
            Image(systemName: icon).font(.ui(13))
                .frame(width: 30, height: 30)
                .foregroundStyle(accent)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13.5, .semibold)).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text(subtitle).font(.mono(11.5)).foregroundStyle(Theme.mutedText).lineLimit(1)
            }
            Spacer(minLength: 6)
            chip().opacity(chipVisible || hovered || selected ? 1 : 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(selected ? Theme.elevated : (hovered ? Theme.fieldBackground : .clear),
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Theme.hairline : .clear, lineWidth: 1))
        .shadow(color: selected ? .black.opacity(0.18) : .clear, radius: selected ? 8 : 0, y: selected ? 3 : 0)
        .contentShape(Rectangle())
        .onHover { hoveredItem = $0 ? hoverKey : (hoveredItem == hoverKey ? nil : hoveredItem) }
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("Delete…", role: .destructive, action: onDelete)
        }
    }

    private var snippetDraftRow: some View {
        draftRow(accent: Theme.snippetAccent, icon: "text.alignleft",
                 title: snippets.draftTitle.isEmpty ? "New snippet" : snippets.draftTitle,
                 subtitle: snippets.draftContent.isEmpty ? "editing…" : String(snippets.draftContent.prefix(60)))
    }
    private var actionDraftRow: some View {
        draftRow(accent: Theme.actionAccent, icon: actions.draftType.symbol,
                 title: actions.draftTitle.isEmpty ? "New action" : actions.draftTitle,
                 subtitle: "editing…")
    }

    private func draftRow(accent: Color, icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.ui(13)).frame(width: 30, height: 30)
                .foregroundStyle(accent).background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13.5, .semibold)).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text(subtitle).font(.mono(11.5)).foregroundStyle(Theme.mutedText).lineLimit(1)
            }
            Spacer()
            Text("DRAFT").font(.mono(9, .bold)).foregroundStyle(accent)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(accent.opacity(0.4), lineWidth: 1))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(accent.opacity(0.45)))
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        Group {
            if library.activeDomain == .snippet, snippets.isEditing {
                SnippetInspector(snippets: snippets, folders: snippets.folders)
            } else if library.activeDomain == .action, actions.isEditing {
                ActionInspector(actions: actions, folders: actions.folders)
            } else {
                inspectorEmpty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.railBackground)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1) }
    }

    private var inspectorEmpty: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right").font(.ui(26)).foregroundStyle(Theme.mutedText)
            Text(library.activeDomain == .snippet ? "Select a snippet, or create one" : "Select an action, or create one")
                .font(.ui(13)).foregroundStyle(Theme.mutedText)
            Button { library.activeDomain == .snippet ? library.newSnippet() : library.newAction() } label: {
                Text(library.activeDomain == .snippet ? "＋ New snippet" : "＋ New action")
                    .font(.ui(12, .semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dialogs

    @ViewBuilder
    private var dialogs: some View {
        SnippetDialogs(viewModel: snippets)
        ActionDialogs(viewModel: actions)
    }
}

/// A type-erased folder so one rail row builder serves both domains.
struct AnyFolder {
    let id: Int64
    let snippet: SnippetFolder?
    let action: ActionFolder?
    init(_ f: SnippetFolder) { id = f.id; snippet = f; action = nil }
    init(_ f: ActionFolder) { id = f.id; snippet = nil; action = f }
}

private extension LibraryView {
    func folderRow(domain: LibraryViewModel.Domain, folder: SnippetFolder, name: String, icon: String, count: Int) -> some View {
        folderRow(domain: domain, folder: AnyFolder(folder), name: name, icon: icon, count: count)
    }
    func folderRow(domain: LibraryViewModel.Domain, folder: ActionFolder, name: String, icon: String, count: Int) -> some View {
        folderRow(domain: domain, folder: AnyFolder(folder), name: name, icon: icon, count: count)
    }
}

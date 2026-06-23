import SwiftUI
import CliplexKit

/// A single clip/snippet row: quick-paste key, content (tag/swatch + title), and
/// trailing metadata (pin + relative time).
struct RowView: View {
    let row: DisplayRow
    let quickIndex: Int?
    let selected: Bool
    let indented: Bool

    private static let height: CGFloat = 34

    var body: some View {
        HStack(spacing: 9) {
            Text(quickLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(selected ? Theme.accent : Theme.mutedText)
                .frame(width: 22, alignment: .center)

            HStack(spacing: 7) {
                leadingAccessory
                Text(row.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if row.pinned {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Theme.accent)
                }
                Text(relativeTime(row.updatedAt))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.mutedText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.selectionBackground : .clear)
        )
        .padding(.horizontal, 4)
        .padding(.leading, indented ? 14 : 0)
        .overlay(alignment: .leading) {
            if indented {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1)
                    .padding(.vertical, 6)
                    .padding(.leading, 10)
            }
        }
        .contentShape(Rectangle())
    }

    private var quickLabel: String {
        guard let quickIndex else { return "" }
        return "⌘\((quickIndex + 1) % 10)"
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if let clipKind = row.clipKind, clipKind == .color, let color = Color(hexString: row.title) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        } else if let tag = tagLabel {
            Text(tag.text)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tag.color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 3.5))
        }
    }

    private var tagLabel: (text: String, color: Color)? {
        switch row.clipKind {
        case .image: return ("IMG", Theme.imageTag)
        case .files: return ("FILE", Theme.filesTag)
        case .color: return ("HEX", Theme.accent)
        case .text, .richtext, .none: return nil
        }
    }
}

/// A section header: an uppercase time/section label, or a tappable, collapsible
/// snippet-folder header with a chevron.
struct HeaderView: View {
    let title: String
    let folderKey: Int64?
    let collapsed: Bool
    let onToggle: (Int64) -> Void

    var body: some View {
        if let folderKey {
            Button {
                onToggle(folderKey)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 13)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .frame(height: 26, alignment: .bottom)
                .padding(.bottom, 5)
        }
    }
}

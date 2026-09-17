import AppKit
import SwiftUI

/// The popup shown by the global hotkey: search field, scrolling list of
/// clipboard entries, and a footer with the Clear All button.
struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    @ObservedObject var store: HistoryStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 380, minHeight: 300)
        .background(VisualEffectBackground())
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) { _ in searchFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: List

    private var content: some View {
        let items = model.filteredItems
        return Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(items) { item in
                                HistoryRow(
                                    item: item,
                                    isSelected: item.id == model.selectedID,
                                    thumbnail: store.thumbnail(for: item),
                                    onSelect: { model.select(item, paste: true) },
                                    onDelete: { model.delete(item.id) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selectedID) { id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(store.items.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(store.items.isEmpty
                 ? "Copy some text or an image and it will appear here."
                 : "Try a different search.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("↩ paste   ⇧↩ copy only   ⌘⌫ delete   esc close")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(role: .destructive) {
                model.clearAllTapped()
            } label: {
                Label(model.clearArmed ? "Confirm Clear All" : "Clear All", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(store.items.isEmpty)
            .help("Permanently delete every stored clipboard item")
            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var countLabel: String {
        let count = store.items.count
        let noun = count == 1 ? "item" : "items"
        let size = ByteCountFormatter.string(fromByteCount: Int64(store.approximateByteCount), countStyle: .file)
        return "\(count) \(noun) · \(size)"
    }
}

// MARK: - Row

struct HistoryRow: View {
    let item: ClipItem
    let isSelected: Bool
    let thumbnail: NSImage?
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind == .image ? "photo" : "text.alignleft")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.06))
                )
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                switch item.kind {
                case .text:
                    Text(item.preview)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                case .image:
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 220, maxHeight: 80, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text(item.preview).font(.system(size: 13))
                    }
                }
                Text("\(Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date())) · \(item.detail)")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering || isSelected {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Delete this item")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Background

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

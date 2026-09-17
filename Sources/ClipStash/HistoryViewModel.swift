import Combine
import Foundation

/// Drives the history popup: search filtering, keyboard selection, and the
/// two-step "Clear All" confirmation.
final class HistoryViewModel: ObservableObject {
    @Published var searchText: String = "" {
        didSet { ensureSelectionValid() }
    }
    @Published var selectedID: UUID?
    @Published var clearArmed: Bool = false
    /// Incremented whenever the panel is shown so the view can refocus search.
    @Published var focusRequest: Int = 0

    let store: HistoryStore

    var onSelect: ((ClipItem, _ paste: Bool) -> Void)?
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var disarmWorkItem: DispatchWorkItem?

    init(store: HistoryStore) {
        self.store = store
        store.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                DispatchQueue.main.async { self?.ensureSelectionValid() }
            }
            .store(in: &cancellables)
    }

    var filteredItems: [ClipItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }
        return store.items.filter { item in
            switch item.kind {
            case .text:
                return (item.text ?? "").localizedCaseInsensitiveContains(query)
            case .image:
                return "image".localizedCaseInsensitiveContains(query)
                    || item.preview.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var selectedItem: ClipItem? {
        guard let selectedID else { return nil }
        return store.items.first { $0.id == selectedID }
    }

    /// Called every time the panel opens.
    func reset() {
        searchText = ""
        disarmClear()
        selectedID = store.items.first?.id
        focusRequest += 1
    }

    func moveSelection(by delta: Int) {
        let items = filteredItems
        guard !items.isEmpty else { selectedID = nil; return }
        guard let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = delta >= 0 ? items.first?.id : items.last?.id
            return
        }
        let next = min(max(index + delta, 0), items.count - 1)
        self.selectedID = items[next].id
    }

    func selectCurrent(paste: Bool) {
        guard let item = selectedItem else { return }
        onSelect?(item, paste)
    }

    func select(_ item: ClipItem, paste: Bool) {
        selectedID = item.id
        onSelect?(item, paste)
    }

    func delete(_ id: UUID) {
        let items = filteredItems
        let wasSelected = selectedID == id
        let index = items.firstIndex { $0.id == id }
        store.remove(id)
        if wasSelected {
            let remaining = filteredItems
            if let index, !remaining.isEmpty {
                selectedID = remaining[min(index, remaining.count - 1)].id
            } else {
                selectedID = nil
            }
        }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        delete(selectedID)
    }

    /// First press arms the button; second press within a few seconds clears.
    func clearAllTapped() {
        if clearArmed {
            store.clearAll()
            disarmClear()
            selectedID = nil
        } else {
            clearArmed = true
            let work = DispatchWorkItem { [weak self] in self?.disarmClear() }
            disarmWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
        }
    }

    func disarmClear() {
        disarmWorkItem?.cancel()
        disarmWorkItem = nil
        clearArmed = false
    }

    private func ensureSelectionValid() {
        let items = filteredItems
        if let selectedID, items.contains(where: { $0.id == selectedID }) { return }
        selectedID = items.first?.id
    }
}

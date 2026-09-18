import Combine
import Foundation

@MainActor
final class RuntimeLogModel: ObservableObject {
    @Published private(set) var entries: [RuntimeLogEntry] = []

    private let store: RuntimeLogStore
    private var fileState: RuntimeLogFileState?

    init(store: RuntimeLogStore = .shared) {
        self.store = store
        reload(force: true)
    }

    func monitor() async {
        while !Task.isCancelled {
            reload()
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    func clear() {
        try? store.clear()
        reload(force: true)
    }

    private func reload(force: Bool = false) {
        let refreshedState = store.fileState()
        guard force || refreshedState != fileState else { return }
        fileState = refreshedState
        entries = (try? store.entries()) ?? []
    }
}

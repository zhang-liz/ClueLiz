import Foundation
import CluelessCore

/// App-side wrapper around the Core ContextStore: file import + persistence
/// of imported text across launches.
final class FileContextStore: ObservableObject {
    let store = ContextStore()
    @Published private(set) var files: [ContextFile] = []

    private let persistenceURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clueless", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("context-files.json")
    }()

    init() {
        load()
        store.onChange = { [weak self] in
            guard let self else { return }
            let files = self.store.files
            DispatchQueue.main.async { self.files = files }
            self.save()
        }
    }

    var combinedTextSnapshot: String {
        store.combinedText(maxChars: 60_000)
    }

    func importFile(at url: URL) throws {
        let file = try FileImporter.importFile(at: url)
        store.add(file)
    }

    func remove(id: UUID) {
        store.remove(id: id)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(store.files) {
            try? data.write(to: persistenceURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let saved = try? JSONDecoder().decode([ContextFile].self, from: data) else { return }
        for file in saved { store.add(file) }
        files = store.files
    }
}

import Foundation

struct ClipboardStoragePaths: Sendable {
    let storageDirectory: URL
    let historyFileURL: URL
    let imagesDirectory: URL
    let textsDirectory: URL
    let searchDirectory: URL
    let searchDatabaseURL: URL

    init(
        storageDirectory: URL,
        historyFileURL: URL,
        imagesDirectory: URL,
        textsDirectory: URL,
        searchDirectory: URL? = nil,
        searchDatabaseURL: URL? = nil
    ) {
        let resolvedSearchDirectory =
            searchDirectory ?? storageDirectory.appendingPathComponent("Search", isDirectory: true)
        self.storageDirectory = storageDirectory
        self.historyFileURL = historyFileURL
        self.imagesDirectory = imagesDirectory
        self.textsDirectory = textsDirectory
        self.searchDirectory = resolvedSearchDirectory
        self.searchDatabaseURL =
            searchDatabaseURL
            ?? resolvedSearchDirectory.appendingPathComponent("index-bootstrap.sqlite")
    }

    init(fileManager: FileManager = .default) throws {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let storageDirectory = appSupport.appendingPathComponent("Buffer", isDirectory: true)
        self.init(
            storageDirectory: storageDirectory,
            historyFileURL: storageDirectory.appendingPathComponent("history.json"),
            imagesDirectory: storageDirectory.appendingPathComponent("images", isDirectory: true),
            textsDirectory: storageDirectory.appendingPathComponent("texts", isDirectory: true)
        )
    }
}

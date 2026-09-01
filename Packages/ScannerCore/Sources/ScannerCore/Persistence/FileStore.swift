import Foundation

/// Page files on disk: `<root>/<documentID>/<pageID>.original.<ext>` and `<pageID>.thumb.jpg`.
/// Every write is atomic with complete file protection (PRD §9 Security). Paths stored in records are
/// relative to `root`, so the store can move without rewriting the database.
public struct FileStore: Sendable {
    public enum Failure: Error { case unreadable(String) }

    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Application Support/Scanner/Documents — backed up with the device like any user document.
    public static func live() throws -> FileStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try FileStore(root: support.appending(path: "Scanner/Documents", directoryHint: .isDirectory))
    }

    public func url(for relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    public func writeOriginal(_ data: Data, extension ext: String, document: UUID, page: UUID) throws -> String {
        let relative = "\(document.uuidString)/\(page.uuidString).original.\(ext)"
        try write(data, to: relative)
        return relative
    }

    public func writeThumbnail(_ data: Data, document: UUID, page: UUID) throws -> String {
        let relative = "\(document.uuidString)/\(page.uuidString).thumb.jpg"
        try write(data, to: relative)
        return relative
    }

    public func read(_ relativePath: String) throws -> Data {
        do { return try Data(contentsOf: url(for: relativePath)) } catch { throw Failure.unreadable(relativePath) }
    }

    public func removePage(originalPath: String, thumbnailPath: String) throws {
        for path in [originalPath, thumbnailPath] {
            let url = url(for: path)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    public func removeDocument(_ id: UUID) throws {
        let directory = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    public func removeAll() throws {
        for item in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try FileManager.default.removeItem(at: item)
        }
    }

    /// Bytes on disk under `root`.
    public func totalSize() -> Int {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    private func write(_ data: Data, to relativePath: String) throws {
        let url = url(for: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

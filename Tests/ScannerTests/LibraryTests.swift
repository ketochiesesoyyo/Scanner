import Testing
import Foundation
import SwiftData
import PDFKit
import ScannerCore
import ImagePipeline
import Recognition
import Export

/// M1.1 / M1.2: originals round-trip byte for byte, and an interrupted session survives a relaunch.
@MainActor
struct LibraryTests {
    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "LibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A library over an on-disk store, so "relaunching" is opening a second one at the same paths.
    private static func openLibrary(in directory: URL) throws -> Library {
        let configuration = ModelConfiguration("LibraryTests", schema: Library.schema, url: directory.appending(path: "library.store"))
        let container = try ModelContainer(for: Library.schema, configurations: [configuration])
        return Library(container: container, files: try FileStore(root: directory.appending(path: "files", directoryHint: .isDirectory)))
    }

    @Test func originalsRoundTripByteForByte() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Library.ephemeral(filesRoot: directory)

        let record = try library.createDraft(source: .files)
        var originals: [Data] = []
        for index in 0..<3 {
            let assets = try PageIngest.prepare(image: Fixtures.page(lines: ["Página \(index + 1)"]))
            originals.append(assets.originalData)
            try await library.addPage(assets, to: record)
        }
        try library.finishCapture(record)

        let reloaded = try #require(try library.allRecords().first)
        #expect(reloaded.state == .ready)
        #expect(reloaded.orderedPages.count == 3)
        for (index, page) in reloaded.orderedPages.enumerated() {
            #expect(page.index == index)
            #expect(try library.files.read(page.originalPath) == originals[index])
            #expect(page.pixelSize == CGSize(width: 1240, height: 1754))
        }
        #if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: library.files.url(for: reloaded.orderedPages[0].originalPath).path)
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        #endif
    }

    @Test func interruptedSessionIsRecoverableAfterRelaunch() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let library = try Self.openLibrary(in: directory)
            let draft = try library.createDraft(source: .documentCamera)
            try await library.addPage(try PageIngest.prepare(image: Fixtures.page(lines: ["uno"])), to: draft)
            try await library.addPage(try PageIngest.prepare(image: Fixtures.page(lines: ["dos"])), to: draft)
            // No finishCapture: the process "dies" here.
        }

        let relaunched = try Self.openLibrary(in: directory)
        let drafts = try relaunched.recoverableDrafts()
        #expect(drafts.count == 1)
        let draft = try #require(drafts.first)
        #expect(draft.state == .capturing)
        #expect(draft.orderedPages.map(\.index) == [0, 1])
        for page in draft.orderedPages {
            #expect(FileManager.default.fileExists(atPath: relaunched.files.url(for: page.originalPath).path))
            #expect(FileManager.default.fileExists(atPath: relaunched.files.url(for: page.thumbnailPath).path))
        }
    }

    @Test func emptyDraftsAreCleanedUp() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Library.ephemeral(filesRoot: directory)
        _ = try library.createDraft(source: .files)
        #expect(try library.recoverableDrafts().isEmpty)
        #expect(try library.allRecords().isEmpty)
    }

    @Test func deleteRemovesRecordAndFiles() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Library.ephemeral(filesRoot: directory)
        let record = try library.createDraft(source: .files)
        try await library.addPage(try PageIngest.prepare(image: Fixtures.page(lines: ["borrar"])), to: record)
        try library.finishCapture(record)
        let documentDirectory = library.files.url(for: record.id.uuidString)
        #expect(FileManager.default.fileExists(atPath: documentDirectory.path))

        try library.delete(record)
        #expect(try library.allRecords().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: documentDirectory.path))
    }

    @Test func deleteEverythingEmptiesTheStore() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Library.ephemeral(filesRoot: directory)
        for _ in 0..<2 {
            let record = try library.createDraft(source: .files)
            try await library.addPage(try PageIngest.prepare(image: Fixtures.page(lines: ["x"])), to: record)
            try library.finishCapture(record)
        }
        try library.deleteEverything()
        #expect(try library.allRecords().isEmpty)
        #expect(library.files.totalSize() == 0)
    }

    @Test func recognitionPersistsAndSnapshotExportsSearchablePDF() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Library.ephemeral(filesRoot: directory)
        let record = try library.createDraft(source: .files)
        let image = Fixtures.page(lines: ["ACTA DE NACIMIENTO", "Registro Civil"])
        let page = try await library.addPage(try PageIngest.prepare(image: image), to: record)
        try library.finishCapture(record)

        let recognition = try await TextRecognizer().recognize(image)
        try library.setRecognition(recognition, for: page)
        #expect(page.recognition?.text.localizedCaseInsensitiveContains("NACIMIENTO") == true)
        #expect(page.confidenceBand != nil)

        let snapshot = library.snapshot(record)
        #expect(snapshot.pages.count == 1)
        #expect(try snapshot.pages[0].loadOriginal().width == 1240)
        let export = try SearchablePDFBuilder(preset: .standard).build(snapshot)
        let pdf = try #require(PDFDocument(data: export.data))
        #expect(pdf.findString("NACIMIENTO", withOptions: .caseInsensitive).count == 1)
    }
}

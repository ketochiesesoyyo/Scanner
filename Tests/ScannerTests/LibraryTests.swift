import Testing
import Foundation
import PDFKit
import ScannerCore
import ImagePipeline
import Recognition
import Export

/// M1.1 / M1.2 on the file-based store: originals round-trip byte for byte, and an interrupted session
/// survives a "relaunch" (a fresh Library over the same directory). No SwiftData — behaves the same on
/// device and here, which the previous model layer did not.
@MainActor
struct LibraryTests {
    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "LibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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

        // A fresh Library reloads the same directory from scan.json.
        let reloaded = try #require(try Library.ephemeral(filesRoot: directory).allRecords().first)
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
            let library = try Library.ephemeral(filesRoot: directory)
            let draft = try library.createDraft(source: .documentCamera)
            try await library.addPage(try PageIngest.prepare(image: Fixtures.page(lines: ["uno"])), to: draft)
            try await library.addPage(try PageIngest.prepare(image: Fixtures.page(lines: ["dos"])), to: draft)
            // No finishCapture: the process "dies" here.
        }

        let relaunched = try Library.ephemeral(filesRoot: directory)
        let drafts = relaunched.recoverableDrafts()
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
        #expect(library.recoverableDrafts().isEmpty)
        #expect(library.allRecords().isEmpty)
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
        #expect(library.allRecords().isEmpty)
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
        #expect(library.allRecords().isEmpty)
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
        try library.setRecognition(recognition, forPage: page.id, inScan: record.id)

        // Reload to prove it persisted to scan.json.
        let reloaded = try #require(try Library.ephemeral(filesRoot: directory).record(id: record.id))
        let reloadedPage = try #require(reloaded.orderedPages.first)
        #expect(reloadedPage.recognition?.text.localizedCaseInsensitiveContains("NACIMIENTO") == true)
        #expect(reloadedPage.confidenceBand != nil)

        let snapshot = library.snapshot(record)
        #expect(snapshot.pages.count == 1)
        #expect(try snapshot.pages[0].loadOriginal().width == 1240)
        let export = try SearchablePDFBuilder(preset: .standard).build(snapshot)
        let pdf = try #require(PDFDocument(data: export.data))
        #expect(pdf.findString("NACIMIENTO", withOptions: .caseInsensitive).count == 1)
    }

    @Test func contentRevisionTracksContentNotRenames() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try Library.ephemeral(filesRoot: directory)
        var record = try library.createDraft(source: .files)
        try await library.addPage(try PageIngest.prepare(image: Fixtures.page(lines: ["a"])), to: record)
        record = try #require(library.record(id: record.id))
        let revisionAfterPage = record.contentRevision

        try library.rename(record, to: "New title")
        let renamed = try #require(library.record(id: record.id))
        #expect(renamed.title == "New title")
        #expect(renamed.contentRevision == revisionAfterPage, "rename must not bump contentRevision")
    }
}

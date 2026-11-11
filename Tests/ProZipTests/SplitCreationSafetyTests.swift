import Foundation
import XCTest
import ProZipShared
@testable import ProZipCore
import ProZipEngines
@testable import ProZipUI

@MainActor
final class SplitCreationSafetyTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("prozip-split-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("payload.bin")
        try Data((0..<12_000).map { UInt8($0 & 255) }).write(to: source)
        return (root, source)
    }

    private func waitForFinish(_ model: ProZipAppViewModel) async throws {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if let phase = model.tasks.first?.phase, [.completed, .failed, .cancelled].contains(phase) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Creation did not finish")
    }

    private func stagedParts(in root: URL) throws -> [URL] {
        let staging = root.appendingPathComponent("staged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return try (1...2).map { index in
            let part = staging.appendingPathComponent("generated.zip").appendingPathExtension(String(format: "%03d", index))
            try Data("staged part \(index)".utf8).write(to: part)
            return part
        }
    }

    private func prepareDraft(source: URL, in root: URL) async throws -> (ProZipAppViewModel, ArchiveBrowsingSession) {
        let session = ArchiveBrowsingSession(url: root.appendingPathComponent("draft.zip"))
        session.addDraftMutation(.addFile(sourceURL: source, archivePath: source.lastPathComponent))
        let model = makeTestAppViewModel()
        model.sessions = [session]
        model.activeSessionID = session.id
        model.saveChanges(for: session)
        for _ in 0..<500 {
            if model.isCreationDialogPresented || model.isAlertPresented { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isCreationDialogPresented)
        return (model, session)
    }

    func testNativeSplitCreationPreservesEveryExistingVolume() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("out.zip")
        let original = Data("existing user volume".utf8)
        for suffix in ["001", "002", "999"] { try original.write(to: base.appendingPathExtension(suffix)) }
        do {
            try await NativeZipEngine().create(sources: [source], at: base, profile: CreationProfile(format: .zip, strength: .store, split: .byCount(2)), password: nil, progress: { _ in })
            XCTFail("Replacing a split family must be rejected")
        } catch {}
        for suffix in ["001", "002", "999"] {
            XCTAssertEqual(try Data(contentsOf: base.appendingPathExtension(suffix)), original, suffix)
        }
    }

    func testNonSplitCreationCannotReplaceTheBaseOfAnExistingSplitFamily() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("out.zip")
        let original = Data("existing base and family".utf8)
        try original.write(to: base)
        try original.write(to: base.appendingPathExtension("001"))
        do {
            try await NativeZipEngine().create(sources: [source], at: base, profile: CreationProfile(format: .zip), password: nil, progress: { _ in })
            XCTFail("A non-split archive must not replace the base of a split family")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: base), original)
        XCTAssertEqual(try Data(contentsOf: base.appendingPathExtension("001")), original)
    }

    func testCreationCallbackAndTaskPointToTheExistingFirstVolume() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("created.zip")
        let model = makeTestAppViewModel()
        var created: URL?
        model.createArchive(sources: [source], destinationURL: base, profile: CreationProfile(format: .zip, strength: .store, split: .byCount(2))) { created = $0 }
        try await waitForFinish(model)
        XCTAssertEqual(model.tasks.first?.phase, .completed)
        let result = try XCTUnwrap(created)
        XCTAssertEqual(result, base.appendingPathExtension("001"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertEqual(model.tasks.first?.outputResultURL, result)
        XCTAssertEqual(model.shelfModel.recentResults.first?.outputURL, result)
        let listed = try await ArchiveEngineBroker.shared.list(result)
        XCTAssertEqual(listed.map(\.path), [source.lastPathComponent])
    }

    func testNativeSizeAndCountSplitsPublishReadableFamilies() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, split) in [("size.zip", CreationProfile.SplitPlan.bySize(1024)), ("count.zip", .byCount(7))] {
            let base = root.appendingPathComponent(name)
            try await NativeZipEngine().create(sources: [source], at: base, profile: CreationProfile(format: .zip, strength: .store, split: split), password: nil, progress: { _ in })
            let first = try SplitArchivePublication.publishedFirstPart(baseURL: base)
            let family = SplitVolumeFamily.resolve(for: first)
            XCTAssertTrue(family.isComplete)
            if name == "count.zip" { XCTAssertEqual(family.volumeURLs.count, 7) }
            else { XCTAssertTrue(try family.volumeURLs.allSatisfy { try Data(contentsOf: $0).count <= 1024 }) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))
            let listed = try await ArchiveEngineBroker.shared.list(first)
            XCTAssertEqual(listed.map(\.path), [source.lastPathComponent])
        }
    }

    func testKeepBothSkipsBaseFilesAndIncompleteVolumeFamilies() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("out.zip")
        let oldFiles = [base.appendingPathExtension("004"), root.appendingPathComponent("out (2).zip.001"), root.appendingPathComponent("out (3).zip")]
        let original = Data("keep every old byte".utf8)
        for file in oldFiles { try original.write(to: file) }
        let model = makeTestAppViewModel()
        var result: URL?
        model.createArchive(sources: [source], destinationURL: base, profile: CreationProfile(format: .zip, strength: .store, split: .byCount(2))) { result = $0 }
        XCTAssertTrue(model.isConflictResolutionPresented)
        XCTAssertTrue(model.tasks.isEmpty)
        model.resolvePendingCreationConflict(.keepBoth)
        model.conflictDialogDidDismiss()
        try await waitForFinish(model)
        XCTAssertEqual(model.tasks.first?.phase, .completed)
        XCTAssertEqual(result, root.appendingPathComponent("out (4).zip.001"))
        for file in oldFiles { XCTAssertEqual(try Data(contentsOf: file), original) }
    }

    func testReplaceSplitFamilyIsRejectedWithoutClearingDraftOrTrashingSources() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, session) = try await prepareDraft(source: source, in: root)
        let staged = try XCTUnwrap(model.creationSources.first).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: staged) }
        let base = root.appendingPathComponent("out.zip")
        let original = Data("old family".utf8)
        try original.write(to: base.appendingPathExtension("001"))
        let completion = try XCTUnwrap(model.creationCompletion)
        model.createArchive(sources: model.creationSources, destinationURL: base, profile: CreationProfile(format: .zip, split: .byCount(2)), moveSourcesToTrash: true, sourcesToTrash: [source], completion: completion)
        XCTAssertTrue(model.isConflictResolutionPresented)
        model.resolvePendingCreationConflict(.replace)
        model.conflictDialogDidDismiss()
        XCTAssertTrue(model.isAlertPresented)
        XCTAssertTrue(model.alertMessage.contains("同时保留"))
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertNotEqual(session.url, base.appendingPathExtension("001"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: base.appendingPathExtension("001")), original)
    }

    func testFailedCreationKeepsDraftAndNeverCallsCompletion() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, session) = try await prepareDraft(source: source, in: root)
        let sources = model.creationSources
        let staged = try XCTUnwrap(sources.first).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.removeItem(at: try XCTUnwrap(sources.first))
        let actualCompletion = try XCTUnwrap(model.creationCompletion)
        var called = false
        let base = root.appendingPathComponent("failed.zip")
        model.createArchive(sources: sources, destinationURL: base, profile: CreationProfile(format: .zip, split: .byCount(2)), moveSourcesToTrash: true, sourcesToTrash: [source]) {
            called = true
            actualCompletion($0)
        }
        try await waitForFinish(model)
        XCTAssertEqual(model.tasks.first?.phase, .failed)
        XCTAssertNil(model.tasks.first?.outputResultURL)
        XCTAssertFalse(called)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try SplitArchivePublication.existingItems(baseURL: base).isEmpty)
    }

    func testSuccessfulSplitCreationBindsDraftToFirstVolumeBeforeClearingIt() async throws {
        let (root, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, session) = try await prepareDraft(source: source, in: root)
        let staged = try XCTUnwrap(model.creationSources.first).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: staged) }
        let completion = try XCTUnwrap(model.creationCompletion)
        let base = root.appendingPathComponent("draft-result.zip")
        model.createArchive(sources: model.creationSources, destinationURL: base, profile: CreationProfile(format: .zip, strength: .store, split: .byCount(3)), completion: completion)
        try await waitForFinish(model)
        for _ in 0..<500 {
            if session.url == base.appendingPathExtension("001"), !session.hasUnsavedChanges { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.tasks.first?.phase, .completed)
        XCTAssertEqual(session.url, base.appendingPathExtension("001"))
        XCTAssertFalse(session.hasUnsavedChanges)
        let listed = try await ArchiveEngineBroker.shared.list(session.url)
        XCTAssertEqual(listed.map(\.path), [source.lastPathComponent])
    }

    func testPublicationRejectsExistingBaseAndInvalidStagedParts() throws {
        let (root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parts = try stagedParts(in: root)
        let base = root.appendingPathComponent("out.zip")
        let original = Data("base file".utf8)
        try original.write(to: base)
        XCTAssertThrowsError(try SplitArchivePublication.publish(stagedParts: parts, baseURL: base))
        XCTAssertEqual(try Data(contentsOf: base), original)
        XCTAssertTrue(parts.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let freeBase = root.appendingPathComponent("free.zip")
        XCTAssertThrowsError(try SplitArchivePublication.publish(stagedParts: [parts[1]], baseURL: freeBase))
        try Data().write(to: parts[0])
        XCTAssertThrowsError(try SplitArchivePublication.publish(stagedParts: parts, baseURL: freeBase))
        XCTAssertTrue(try SplitArchivePublication.existingItems(baseURL: freeBase).isEmpty)
    }

    func testPartialPublicationRollsBackOnlyNewVolumesAndPreservesRacingFile() throws {
        let (root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parts = try stagedParts(in: root)
        let base = root.appendingPathComponent("out.zip")
        let foreign = Data("concurrent user file".utf8)
        var moved = 0
        XCTAssertThrowsError(try SplitArchivePublication.publish(stagedParts: parts, baseURL: base, move: { source, destination in
            moved += 1
            if moved == 2 {
                try foreign.write(to: destination, options: .withoutOverwriting)
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.moveItem(at: source, to: destination)
        }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathExtension("001").path))
        XCTAssertEqual(try Data(contentsOf: base.appendingPathExtension("002")), foreign)
    }

    func testRollbackDoesNotRemoveAUserReplacementOfANewVolume() throws {
        let (root, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parts = try stagedParts(in: root)
        let base = root.appendingPathComponent("out.zip")
        let replacement = Data("user replacement must survive".utf8)
        var moved = 0
        XCTAssertThrowsError(try SplitArchivePublication.publish(stagedParts: parts, baseURL: base, move: { source, destination in
            moved += 1
            if moved == 2 {
                let first = base.appendingPathExtension("001")
                try FileManager.default.removeItem(at: first)
                try replacement.write(to: first)
                throw CocoaError(.fileWriteUnknown)
            }
            try FileManager.default.moveItem(at: source, to: destination)
        }))
        XCTAssertEqual(try Data(contentsOf: base.appendingPathExtension("001")), replacement)
    }
}

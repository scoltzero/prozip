import XCTest
import Foundation
import ProZipShared
@testable import ProZipEngines

final class SevenZipWriteEncryptionTests: XCTestCase {
    private let fixturePassword = "public-regression-password"
    private let engine = SevenZipEngine()

    private func withFixture(_ body: (URL) async throws -> Void) async throws {
        guard SevenZipEngine.resolveBinaryURL() != nil else { throw XCTSkip("7-Zip is not installed") }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prozip-write-encryption-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    private func run(_ arguments: [String], input: String? = nil) async throws -> ProcessCancellationController.ProcessResult {
        let binary = try XCTUnwrap(SevenZipEngine.resolveBinaryURL())
        return try await ProcessCancellationController.run(
            executableURL: binary, arguments: arguments, stdinData: input.map { Data($0.utf8) }
        )
    }

    private func source(_ name: String, content: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    private func makeRawArchive(_ sources: [URL], at archive: URL, format: ArchiveFormat = .sevenZip,
                                password: String? = nil, headers: Bool = false) async throws {
        var args = ["a", format == .zip ? "-tzip" : "-t7z", "-mx=1"]
        if password != nil { args.append("-p") }
        if headers { args.append("-mhe=on") }
        args += ["--", archive.path] + sources.map(\.path)
        let input = password.map { "\($0)\n\($0)\n" }
        let result = try await run(args, input: input)
        XCTAssertEqual(result.exitCode, 0, result.combinedOutputString)
        guard result.exitCode == 0 else { throw ProZipError.invalidArchive("Could not create public test fixture") }
    }

    private func listRaw(_ archive: URL, password: String? = nil) async throws -> ProcessCancellationController.ProcessResult {
        try await run(["l", "-slt", "-ba", "--", archive.path], input: password.map { "\($0)\n" })
    }

    private func extractRaw(_ path: String, from archive: URL,
                            password: String? = nil) async throws -> ProcessCancellationController.ProcessResult {
        try await run(["x", "-so", "-y", "--", archive.path, path], input: password.map { "\($0)\n" })
    }

    private func assertContents(_ expected: [String: String], in archive: URL, password: String? = nil) async throws {
        let listed = try await engine.list(archive, password: password, progress: { _ in })
        XCTAssertEqual(Set(listed.filter { !$0.isDirectory }.map(\.path)), Set(expected.keys))
        for (path, content) in expected {
            let extracted = try await extractRaw(path, from: archive, password: password)
            XCTAssertEqual(extracted.exitCode, 0, extracted.combinedOutputString)
            XCTAssertEqual(extracted.stdout, Data(content.utf8))
        }
        let tested = try await run(["t", "-y", "--", archive.path], input: password.map { "\($0)\n" })
        XCTAssertEqual(tested.exitCode, 0, tested.combinedOutputString)
    }

    func testActualPipedPasswordProtocolRequiresConfirmation() async throws {
        try await withFixture { root in
            let file = try source("public.txt", content: "public fixture\n", in: root)
            let failed = try await run(["a", "-t7z", "-p", "--", root.appendingPathComponent("one-line.7z").path, file.path],
                                       input: "\(fixturePassword)\n")
            XCTAssertEqual(failed.exitCode, 2)
            XCTAssertTrue(failed.combinedOutputString.contains("password verification failed"))
            let archive = root.appendingPathComponent("confirmed.7z")
            let confirmed = try await run(["a", "-t7z", "-p", "--", archive.path, file.path],
                                          input: "\(fixturePassword)\n\(fixturePassword)\n")
            let metadata = try await listRaw(archive)
            XCTAssertEqual(confirmed.exitCode, 0)
            XCTAssertEqual(metadata.exitCode, 0)
            XCTAssertTrue(metadata.combinedOutputString.contains("Encrypted = +"))
            print("7-Zip pipe protocol: one password line exit=\(failed.exitCode); two lines exit=\(confirmed.exitCode); Encrypted=+")
        }
    }

    func testPlain7zAndZipCreationNeverEncryptsWithADummyPassword() async throws {
        for format in [ArchiveFormat.sevenZip, .zip] {
            for password: String? in [nil, ""] {
                try await withFixture { root in
                    let file = try source("public.txt", content: "public plaintext fixture\n", in: root)
                    let archive = root.appendingPathComponent("plain.\(format == .zip ? "zip" : "7z")")
                    try await engine.create(sources: [file], at: archive, profile: CreationProfile(format: format),
                                            password: password, progress: { _ in })
                    let metadata = try await listRaw(archive)
                    XCTAssertEqual(metadata.exitCode, 0)
                    XCTAssertTrue(metadata.combinedOutputString.contains("Encrypted = -"))
                    XCTAssertFalse(metadata.combinedOutputString.contains("Encrypted = +"))
                    try await assertContents(["public.txt": "public plaintext fixture\n"], in: archive)
                }
            }
        }
    }

    private func assertEncryptedCreation(format: ArchiveFormat, headers: Bool) async throws {
        try await withFixture { root in
            let file = try source("public.txt", content: "public encrypted fixture\n", in: root)
            let archive = root.appendingPathComponent("encrypted.\(format == .zip ? "zip" : "7z")")
            let profile = CreationProfile(format: format, password: fixturePassword, encryptHeaders: headers)
            try await engine.create(sources: [file], at: archive, profile: profile,
                                    password: fixturePassword, progress: { _ in })
            let publicListing = try await listRaw(archive)
            XCTAssertEqual(publicListing.exitCode, headers ? 2 : 0)
            if !headers { XCTAssertTrue(publicListing.combinedOutputString.contains("Path = public.txt")) }
            let metadata = try await listRaw(archive, password: fixturePassword)
            XCTAssertEqual(metadata.exitCode, 0)
            XCTAssertTrue(metadata.combinedOutputString.contains("Encrypted = +"))
            XCTAssertTrue(metadata.combinedOutputString.contains(format == .zip ? "ZipCrypto" : "7zAES"))
            let missing = try await extractRaw("public.txt", from: archive)
            let wrong = try await extractRaw("public.txt", from: archive, password: "public-wrong-password")
            XCTAssertEqual(missing.exitCode, 2)
            XCTAssertEqual(wrong.exitCode, 2)
            try await assertContents(["public.txt": "public encrypted fixture\n"], in: archive, password: fixturePassword)
            print("7-Zip encrypted \(format), headers=\(headers): no-password list=\(publicListing.exitCode); missing/wrong member=\(missing.exitCode)/\(wrong.exitCode); correct round trip=0")
        }
    }

    func testSevenZipBodyEncryptionWithPublicHeaders() async throws {
        try await assertEncryptedCreation(format: .sevenZip, headers: false)
    }

    func testZipBodyEncryption() async throws {
        try await assertEncryptedCreation(format: .zip, headers: false)
    }

    func testSevenZipHeaderEncryption() async throws {
        try await assertEncryptedCreation(format: .sevenZip, headers: true)
    }

    func testSevenZipConsolePasswordKeepsUnicodeAndOuterWhitespace() async throws {
        try await withFixture { root in
            let file = try source("public.txt", content: "public Unicode fixture\n", in: root)
            let archive = root.appendingPathComponent("unicode-password.7z")
            let password = " 公开测试-密码 "
            try await engine.create(sources: [file], at: archive,
                profile: CreationProfile(format: .sevenZip, password: password),
                password: password, progress: { _ in })
            let trimmed = try await extractRaw("public.txt", from: archive, password: password.trimmingCharacters(in: .whitespaces))
            XCTAssertEqual(trimmed.exitCode, 2)
            try await assertContents(["public.txt": "public Unicode fixture\n"], in: archive, password: password)
        }
    }

    func testHeaderProbeAndListHandleP7zipSpellingAndInlinePrompt() async throws {
        try await withFixture { root in
            let file = try source("first.txt", content: "public header fixture\n", in: root)
            let archive = root.appendingPathComponent("headers.7z")
            try await makeRawArchive([file], at: archive, password: fixturePassword, headers: true)
            let descriptor = try await engine.probe(archive)
            XCTAssertTrue(descriptor.isEncrypted)
            XCTAssertTrue(descriptor.hasEncryptedHeaders)
            do {
                _ = try await engine.list(archive, password: nil, progress: { _ in })
                XCTFail("Header-encrypted archive must require its password")
            } catch ProZipError.passwordRequired { }
            let entries = try await engine.list(archive, password: fixturePassword, progress: { _ in })
            XCTAssertEqual(entries.map(\.path), ["first.txt"])
            XCTAssertEqual(entries.map(\.isEncrypted), [true])
        }
    }

    func testCreationArgvUsesBarePasswordSwitchAndKeepsReadFailFastRules() {
        let protected = SevenZipEngine.buildCommandArguments(
            subcommand: "a", archivePath: "/tmp/public.7z", extraArgs: ["-t7z"], hasPassword: true
        )
        XCTAssertEqual(protected.filter { $0.hasPrefix("-p") }, ["-p"])
        XCTAssertFalse(protected.contains(fixturePassword))
        let plain = SevenZipEngine.buildCommandArguments(subcommand: "a", archivePath: "/tmp/public.7z", hasPassword: false)
        XCTAssertFalse(plain.contains { $0.hasPrefix("-p") })
        for command in ["l", "x"] {
            let locked = SevenZipEngine.buildCommandArguments(subcommand: command, archivePath: "/tmp/public.7z", hasPassword: false)
            XCTAssertTrue(locked.contains("-p__ARCZIP_NO_PASSWORD__"))
            let unlocked = SevenZipEngine.buildCommandArguments(subcommand: command, archivePath: "/tmp/public.7z", hasPassword: true)
            XCTAssertFalse(unlocked.contains { $0.hasPrefix("-p") })
        }
    }

    func testCreateRejectsCRLFAndNULPasswordsBeforePublishingAnything() async throws {
        for password in ["public\nsecond", "public\rsecond", "public\u{0}second"] {
            try await withFixture { root in
                let file = try source("public.txt", content: "public fixture\n", in: root)
                let archive = root.appendingPathComponent("invalid.7z")
                do {
                    try await engine.create(sources: [file], at: archive, profile: CreationProfile(format: .sevenZip),
                                            password: password, progress: { _ in })
                    XCTFail("Console-delimited password must be rejected")
                } catch ProZipError.invalidCreationProfile { }
                XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
            }
        }
    }

    func testUnfulfillableHeaderEncryptionIsRejected() async throws {
        for (format, password) in [(ArchiveFormat.sevenZip, nil as String?), (.zip, fixturePassword as String?)] {
            try await withFixture { root in
                let file = try source("public.txt", content: "public fixture\n", in: root)
                let archive = root.appendingPathComponent("invalid")
                do {
                    try await engine.create(sources: [file], at: archive,
                        profile: CreationProfile(format: format, password: password, encryptHeaders: true),
                        password: password, progress: { _ in })
                    XCTFail("Unsupported header protection must not be silently ignored")
                } catch ProZipError.invalidCreationProfile { }
                XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
            }
        }
    }

    private func assertMutationProtection(format: ArchiveFormat, password: String?, headers: Bool) async throws {
        try await withFixture { root in
            let first = try source("first.txt", content: "old first\n", in: root)
            let second = try source("second.txt", content: "unchanged second\n", in: root)
            let replacement = try source("replacement.txt", content: "replaced first\n", in: root)
            let addition = try source("addition.txt", content: "added nested\n", in: root)
            let archive = root.appendingPathComponent("edited.\(format == .zip ? "zip" : "7z")")
            try await makeRawArchive([first, second], at: archive, format: format, password: password, headers: headers)
            // Deliberately omit encryptHeaders in the profile: editing must retain the source policy.
            try await engine.applyMutations([
                .replaceEntry(archivePath: "first.txt", replacementSourceURL: replacement),
                .addFile(sourceURL: addition, archivePath: "nested/added.txt")
            ], to: archive, outputURL: archive, profile: CreationProfile(format: format),
                password: password, progress: { _ in })
            let publicListing = try await listRaw(archive)
            XCTAssertEqual(publicListing.exitCode, headers ? 2 : 0)
            let entries = try await engine.list(archive, password: password, progress: { _ in })
            XCTAssertTrue(entries.filter { !$0.isDirectory && $0.uncompressedSize > 0 }
                .allSatisfy { $0.isEncrypted == (password != nil) })
            if password != nil {
                let missing = try await extractRaw("nested/added.txt", from: archive)
                let wrong = try await extractRaw("nested/added.txt", from: archive, password: "public-wrong-password")
                XCTAssertEqual(missing.exitCode, 2)
                XCTAssertEqual(wrong.exitCode, 2)
            }
            try await assertContents([
                "first.txt": "replaced first\n", "second.txt": "unchanged second\n", "nested/added.txt": "added nested\n"
            ], in: archive, password: password)
        }
    }

    func testPlainSevenZipAdditionAndReplacementRemainPlain() async throws {
        try await assertMutationProtection(format: .sevenZip, password: nil, headers: false)
    }

    func testPlainZipAdditionAndReplacementRemainPlain() async throws {
        try await assertMutationProtection(format: .zip, password: nil, headers: false)
    }

    func testEncryptedSevenZipAdditionAndReplacementUseTheExistingPassword() async throws {
        try await assertMutationProtection(format: .sevenZip, password: fixturePassword, headers: false)
    }

    func testHeaderEncryptedSevenZipAdditionAndReplacementPreserveHeaderProtection() async throws {
        try await assertMutationProtection(format: .sevenZip, password: fixturePassword, headers: true)
    }

    func testEncryptedZipAdditionAndReplacementUseTheExistingPassword() async throws {
        try await assertMutationProtection(format: .zip, password: fixturePassword, headers: false)
    }

    func testEncryptedEditsWithMissingOrWrongPasswordKeepTheOriginalBytes() async throws {
        for headers in [false, true] {
            for password: String? in [nil, "public-wrong-password"] {
                try await withFixture { root in
                    let original = try source("original.txt", content: "public original\n", in: root)
                    let added = try source("added.txt", content: "public addition\n", in: root)
                    let archive = root.appendingPathComponent("existing.7z")
                    try await makeRawArchive([original], at: archive, password: fixturePassword, headers: headers)
                    let before = try Data(contentsOf: archive)
                    do {
                        try await engine.applyMutations([.addFile(sourceURL: added, archivePath: "added.txt")],
                            to: archive, outputURL: archive, profile: CreationProfile(format: .sevenZip),
                            password: password, progress: { _ in })
                        XCTFail("An unauthenticated edit must not mix passwords or plaintext")
                    } catch { }
                    XCTAssertEqual(try Data(contentsOf: archive), before)
                }
            }
        }
    }

    func testEveryPublicWriteBoundaryRejectsConsoleDelimiters() async throws {
        for password in ["public\nsecond", "public\rsecond", "public\u{0}second"] {
            try await withFixture { root in
                let file = try source("public.txt", content: "public fixture\n", in: root)
                let added = try source("added.txt", content: "public addition\n", in: root)
                let archive = root.appendingPathComponent("existing.7z")
                try await makeRawArchive([file], at: archive)
                let before = try Data(contentsOf: archive)
                for mutation in [
                    ArchiveMutation.addFile(sourceURL: added, archivePath: "added.txt"),
                    .renameEntry(oldArchivePath: "public.txt", newArchivePath: "renamed.txt"),
                    .deleteEntry(archivePath: "public.txt")
                ] {
                    do {
                        try await engine.applyMutations([mutation], to: archive, outputURL: archive,
                            profile: CreationProfile(format: .sevenZip), password: password, progress: { _ in })
                        XCTFail("Invalid console password must fail before any write")
                    } catch ProZipError.invalidCreationProfile { }
                    XCTAssertEqual(try Data(contentsOf: archive), before)
                }
            }
        }
    }

    func testMultiPasswordSourceIsRejectedInsteadOfSilentlyMixingAnotherKey() async throws {
        try await withFixture { root in
            let old = try source("old.txt", content: "public old\n", in: root)
            let other = try source("other.txt", content: "public other\n", in: root)
            let addition = try source("addition.txt", content: "public addition\n", in: root)
            let archive = root.appendingPathComponent("different-passwords.7z")
            try await makeRawArchive([old], at: archive, password: fixturePassword)
            let append = try await run(["a", "-p", "--", archive.path, other.path],
                                       input: "public-second-password\npublic-second-password\n")
            XCTAssertEqual(append.exitCode, 0)
            let before = try Data(contentsOf: archive)
            do {
                try await engine.applyMutations([.addFile(sourceURL: addition, archivePath: "addition.txt")],
                    to: archive, outputURL: archive, profile: CreationProfile(format: .sevenZip),
                    password: fixturePassword, progress: { _ in })
                XCTFail("One supplied password cannot authenticate all encrypted groups")
            } catch { }
            XCTAssertEqual(try Data(contentsOf: archive), before)
        }
    }

    func testPayloadEditsCannotIntroduceEncryptionOnlyForNewMembersOfAPlainArchive() async throws {
        try await withFixture { root in
            let old = try source("old.txt", content: "public old\n", in: root)
            let added = try source("added.txt", content: "public addition\n", in: root)
            let archive = root.appendingPathComponent("plain.7z")
            try await makeRawArchive([old], at: archive)
            let before = try Data(contentsOf: archive)
            do {
                try await engine.applyMutations([.addFile(sourceURL: added, archivePath: "added.txt")],
                    to: archive, outputURL: archive, profile: CreationProfile(format: .sevenZip),
                    password: fixturePassword, progress: { _ in })
                XCTFail("Editing must not silently create a mixture of plain and encrypted members")
            } catch ProZipError.invalidCreationProfile { }
            XCTAssertEqual(try Data(contentsOf: archive), before)
        }
    }

    func testAddingContentAfterOnlyEmptyEncryptedMembersKeepsPasswordProtection() async throws {
        for format in [ArchiveFormat.sevenZip, .zip] {
            try await withFixture { root in
                let empty = try source("empty.txt", content: "", in: root)
                let added = try source("added.txt", content: "public addition\n", in: root)
                let archive = root.appendingPathComponent(format == .zip ? "empty.zip" : "empty.7z")
                try await makeRawArchive([empty], at: archive, format: format, password: fixturePassword)
                try await engine.applyMutations([.addFile(sourceURL: added, archivePath: "added.txt")],
                    to: archive, outputURL: archive, profile: CreationProfile(format: format),
                    password: fixturePassword, progress: { _ in })
                let without = try await extractRaw("added.txt", from: archive)
                XCTAssertEqual(without.exitCode, 2)
                try await assertContents(["empty.txt": "", "added.txt": "public addition\n"],
                                         in: archive, password: fixturePassword)
            }
        }
    }

    func testSplitSevenZipCreationRetainsRequestedEncryption() async throws {
        for password: String? in [nil, fixturePassword] {
            try await withFixture { root in
                var state: UInt64 = 7
                let bytes = (0..<4096).map { _ -> UInt8 in
                    state = state &* 6364136223846793005 &+ 1
                    return UInt8(truncatingIfNeeded: state >> 32)
                }
                let file = root.appendingPathComponent("public.bin")
                try Data(bytes).write(to: file)
                let archive = root.appendingPathComponent("split.7z")
                let profile = CreationProfile(format: .sevenZip, strength: .store, split: .bySize(1024),
                                              password: password, encryptHeaders: password != nil)
                try await engine.create(sources: [file], at: archive, profile: profile,
                                        password: password, progress: { _ in })
                let first = root.appendingPathComponent("split.7z.001")
                XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
                let descriptor = try await engine.probe(first)
                XCTAssertEqual(descriptor.hasEncryptedHeaders, password != nil)
                if password != nil {
                    do {
                        _ = try await engine.list(first, password: nil, progress: { _ in })
                        XCTFail("Encrypted split headers must require a password")
                    } catch ProZipError.passwordRequired { }
                }
                let extracted = try await extractRaw("public.bin", from: first, password: password)
                XCTAssertEqual(extracted.exitCode, 0, extracted.combinedOutputString)
                XCTAssertEqual(extracted.stdout, Data(bytes))
                let entries = try await engine.list(first, password: password, progress: { _ in })
                XCTAssertEqual(entries.map(\.isEncrypted), [password != nil])
            }
        }
    }

    func testSplitCreationNeverReplacesAnExistingBaseOrResidualVolume() async throws {
        for suffix in ["", ".007"] {
            try await withFixture { root in
                let file = try source("public.txt", content: "public split fixture\n", in: root)
                let base = root.appendingPathComponent("existing.7z")
                let old = root.appendingPathComponent("existing.7z"+suffix)
                let sentinel = Data("public pre-existing data\n".utf8)
                try sentinel.write(to: old)
                do {
                    try await engine.create(sources: [file], at: base,
                        profile: CreationProfile(format: .sevenZip, split: .bySize(1024)),
                        password: nil, progress: { _ in })
                    XCTFail("Existing split family must not be replaced")
                } catch ProZipError.destinationNotWritable { }
                XCTAssertEqual(try Data(contentsOf: old), sentinel)
                XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathExtension("001").path))
            }
        }
    }

    func testSplitCreationRejectsMoreThan999PartsWithoutPublishingAPrefix() async throws {
        try await withFixture { root in
            let file = root.appendingPathComponent("public.bin")
            try Data(repeating: 0x41, count: 1024 * 1000).write(to: file)
            let archive = root.appendingPathComponent("too-many.7z")
            do {
                try await engine.create(sources: [file], at: archive,
                    profile: CreationProfile(format: .sevenZip, strength: .store, split: .bySize(1024)),
                    password: nil, progress: { _ in })
                XCTFail("Four-digit parts must not be silently discarded")
            } catch ProZipError.splitVolumeIncomplete { }
            XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathExtension("001").path))
        }
    }

    func testSingleArchiveCreationCannotHideAnExistingSplitFamily() async throws {
        for format in [ArchiveFormat.sevenZip, .zip] {
            try await withFixture { root in
                let file = try source("public.txt", content: "public source\n", in: root)
                let base = root.appendingPathComponent(format == .zip ? "existing.zip" : "existing.7z")
                let old = root.appendingPathComponent(format == .zip ? "existing.z01" : "existing.7z.007")
                let sentinel = Data("public existing volume\n".utf8)
                try sentinel.write(to: old)
                do {
                    try await engine.create(sources: [file], at: base, profile: CreationProfile(format: format),
                                            password: nil, progress: { _ in })
                    XCTFail("A new base must not shadow an existing split family")
                } catch ProZipError.destinationNotWritable { }
                XCTAssertEqual(try Data(contentsOf: old), sentinel)
                XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))
            }
        }
    }

    func testEncryptedMemberRangesContainOnlyTheRequestedPlaintextBytes() async throws {
        try await withFixture { root in
            var state: UInt64 = 19
            let bytes = (0..<(1024 * 1024)).map { _ -> UInt8 in
                state = state &* 6364136223846793005 &+ 1
                return UInt8(truncatingIfNeeded: state >> 32)
            }
            let data = Data(bytes)
            let file = root.appendingPathComponent("public.bin")
            try data.write(to: file)
            for headers in [false, true] {
                let archive = root.appendingPathComponent(headers ? "private-headers.7z" : "public-headers.7z")
                try await makeRawArchive([file], at: archive, password: fixturePassword, headers: headers)
                let entries = try await engine.list(archive, password: fixturePassword, progress: { _ in })
                let entry = try XCTUnwrap(entries.first)
                let range: Range<Int64> = 8192..<40960
                var actual = Data()
                for try await chunk in try await engine.openMember(entry, in: archive, password: fixturePassword, range: range) {
                    actual.append(chunk)
                }
                XCTAssertEqual(actual, data.subdata(in: Int(range.lowerBound)..<Int(range.upperBound)))
            }
        }
    }

    func testKnownFullRangeStillRejectsATailCRCError() async throws {
        try await withFixture { root in
            let data = Data(repeating: 0x62, count: 65536)
            let file = root.appendingPathComponent("public.bin")
            try data.write(to: file)
            let archive = root.appendingPathComponent("crc.zip")
            let created = try await run(["a", "-tzip", "-mx=0", "--", archive.path, file.path])
            XCTAssertEqual(created.exitCode, 0)
            let listed = try await engine.list(archive, password: nil, progress: { _ in })
            let entry = try XCTUnwrap(listed.first)
            var bytes = try Data(contentsOf: archive)
            XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
            XCTAssertEqual(bytes[8], 0) // Stored data lets 7-Zip emit all bytes before checking CRC.
            let nameLength = Int(bytes[26]) | Int(bytes[27]) << 8
            let extraLength = Int(bytes[28]) | Int(bytes[29]) << 8
            let payload = 30 + nameLength + extraLength
            bytes[payload + data.count - 1] ^= 1
            try bytes.write(to: archive)
            let direct = try await extractRaw("public.bin", from: archive)
            XCTAssertEqual(direct.exitCode, 2)
            XCTAssertEqual(direct.stdout.count, data.count)
            do {
                for try await _ in try await engine.openMember(entry, in: archive, password: nil,
                                                               range: 0..<entry.uncompressedSize) { }
                XCTFail("A range covering the whole member must retain its final CRC check")
            } catch ProZipError.corruptedArchive { }
            print("7-Zip corrupt stored member: emitted=\(direct.stdout.count), exit=\(direct.exitCode); full-range read rejected")
        }
    }

    private func assertSevenCountParts(_ base: URL, expected: [String: String],
                                       password: String?, headers: Bool) async throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))
        let first = base.appendingPathExtension("001")
        let family = SplitVolumeFamily.resolve(for: first)
        XCTAssertTrue(family.isComplete)
        XCTAssertFalse(family.hasEmptyVolume)
        XCTAssertEqual(family.volumeURLs.map(\.lastPathComponent),
                       (1...7).map { base.lastPathComponent + String(format: ".%03d", $0) })
        let sizes = try family.volumeURLs.map {
            try Data(contentsOf: $0).count
        }
        XCTAssertTrue(sizes.allSatisfy { $0 > 0 })
        XCTAssertLessThanOrEqual((sizes.max() ?? 0) - (sizes.min() ?? 0), 1)
        let publicListing = try await listRaw(first)
        XCTAssertEqual(publicListing.exitCode, headers ? 2 : 0)
        try await assertContents(expected, in: first, password: password)
        var joined = Data()
        for part in family.volumeURLs { joined.append(try Data(contentsOf: part)) }
        let reconstructed = base.deletingLastPathComponent().appendingPathComponent("joined-" + base.lastPathComponent)
        try joined.write(to: reconstructed)
        try await assertContents(expected, in: reconstructed, password: password)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: base.deletingLastPathComponent().path)
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(".prozip-create-staging-") || $0.hasPrefix(".prozip-parts-") })
    }

    func testByCountHighlyCompressibleFileProducesSevenRealEqualParts() async throws {
        for (format, password, headers) in [
            (ArchiveFormat.sevenZip, nil as String?, false),
            (.sevenZip, fixturePassword as String?, true),
            (.zip, fixturePassword as String?, false)
        ] {
            try await withFixture { root in
                let content = String(repeating: "public compressible fixture\n", count: 4096)
                let file = try source("public.txt", content: content, in: root)
                let base = root.appendingPathComponent(format == .zip ? "seven.zip" : "seven.7z")
                let profile = CreationProfile(format: format, split: .byCount(7), password: password, encryptHeaders: headers)
                try await engine.create(sources: [file], at: base, profile: profile, password: password, progress: { _ in
                    XCTAssertFalse(FileManager.default.fileExists(atPath: base.path), "Complete archive must stay private")
                })
                try await assertSevenCountParts(base, expected: ["public.txt": content], password: password, headers: headers)
            }
        }
    }

    func testByCountHighlyCompressibleDirectoryProducesSevenPartsAndRoundTripsEveryFile() async throws {
        for headers in [false, true] {
            try await withFixture { root in
                let directory = root.appendingPathComponent("public-folder", isDirectory: true)
                let nested = directory.appendingPathComponent("nested", isDirectory: true)
                try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
                let first = String(repeating: "public repeated first\n", count: 4096)
                let second = String(repeating: "public repeated second\n", count: 6144)
                try Data(first.utf8).write(to: directory.appendingPathComponent("first.txt"))
                try Data(second.utf8).write(to: nested.appendingPathComponent("second.txt"))
                let base = root.appendingPathComponent("seven.7z")
                let password = headers ? fixturePassword : nil
                try await engine.create(sources: [directory], at: base,
                    profile: CreationProfile(format: .sevenZip, split: .byCount(7), password: password, encryptHeaders: headers),
                    password: password, progress: { _ in
                        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path), "Complete archive must stay private")
                    })
                try await assertSevenCountParts(base, expected: [
                    "public-folder/first.txt": first, "public-folder/nested/second.txt": second
                ], password: password, headers: headers)
            }
        }
    }

    func testRenameAndDeleteRetainRemainingSevenZipEncryption() async throws {
        for (format, password, headers) in [
            (ArchiveFormat.sevenZip, nil as String?, false), (.sevenZip, fixturePassword as String?, false),
            (.sevenZip, fixturePassword as String?, true), (.zip, nil as String?, false), (.zip, fixturePassword as String?, false)
        ] {
            try await withFixture { root in
                let first = try source("first.txt", content: "public first\n", in: root)
                let second = try source("second.txt", content: "public second\n", in: root)
                let archive = root.appendingPathComponent(format == .zip ? "rename-delete.zip" : "rename-delete.7z")
                try await makeRawArchive([first, second], at: archive, format: format, password: password, headers: headers)
                try await engine.applyMutations([
                    .renameEntry(oldArchivePath: "first.txt", newArchivePath: "renamed.txt"),
                    .deleteEntry(archivePath: "second.txt")
                ], to: archive, outputURL: archive, profile: CreationProfile(format: format),
                    password: password, progress: { _ in })
                let publicListing = try await listRaw(archive)
                XCTAssertEqual(publicListing.exitCode, headers ? 2 : 0)
                let entries = try await engine.list(archive, password: password, progress: { _ in })
                XCTAssertEqual(entries.map(\.isEncrypted), [password != nil])
                try await assertContents(["renamed.txt": "public first\n"], in: archive, password: password)
            }
        }
    }
}

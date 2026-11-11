import XCTest
import Foundation
import CryptoKit
@testable import ProZipCore

final class TestPasswordBookKeyStore: PasswordBookKeyStore, @unchecked Sendable {
    struct Record {
        var key: Data
        var requiresUserPresence: Bool
    }
    private let lock = NSLock()
    private var records: [String: Record] = [:]
    private var reads: [Bool] = []
    var shouldFailSaving = false
    var shouldFailLoading = false
    var shouldFailRemoving = false
    var supportsAuthentication = true
    var authenticationAllowed = true
    var authenticatedKeyOverride: Data?
    var onSave: (() -> Void)?
    var onAuthenticatedRead: (() -> Void)?

    var savedKeys: [String: Record] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    var authenticatedReadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads.filter { $0 }.count
    }

    func saveKey(_ key: Data, id: String, requiresUserPresence: Bool) throws {
        guard !shouldFailSaving, !requiresUserPresence || supportsAuthentication else {
            throw CocoaError(.fileWriteNoPermission)
        }
        lock.lock()
        records[id] = Record(key: key, requiresUserPresence: requiresUserPresence)
        lock.unlock()
        onSave?()
    }

    func loadKey(id: String, authenticationReason: String?) throws -> Data {
        lock.lock()
        let record = records[id]
        reads.append(authenticationReason != nil)
        lock.unlock()
        guard !shouldFailLoading, let record else { throw CocoaError(.fileReadNoPermission) }
        if record.requiresUserPresence {
            guard authenticationReason != nil, authenticationAllowed else { throw CocoaError(.userCancelled) }
            onAuthenticatedRead?()
            return authenticatedKeyOverride ?? record.key
        }
        return record.key
    }

    func removeKey(id: String) throws {
        guard !shouldFailRemoving else { throw CocoaError(.fileWriteNoPermission) }
        lock.lock()
        records.removeValue(forKey: id)
        lock.unlock()
    }

    func canAuthenticate() -> Bool { supportsAuthentication }

    func containsProtectedKey(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return records[id]?.requiresUserPresence == true
    }
}

final class PasswordVaultTests: XCTestCase {
    private let keyStore = TestPasswordBookKeyStore()

    private func makeBook(_ url: URL) -> PasswordBook {
        PasswordBook(storageURL: url, keyStore: keyStore)
    }

    private func withTemporaryVault(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prozip-vault-tests-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(directory.appendingPathComponent("password_book.dat"))
    }

    // A regular file in place of the parent makes writes fail even when tests run as root.
    private func withUnavailableParent(of url: URL, _ body: () throws -> Void) throws {
        let parent = url.deletingLastPathComponent()
        let backup = parent.deletingLastPathComponent().appendingPathComponent("saved-vault")
        try FileManager.default.moveItem(at: parent, to: backup)
        try Data("not a directory".utf8).write(to: parent)
        defer {
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.moveItem(at: backup, to: parent)
        }
        try body()
    }

    private struct LegacyStore: Codable {
        var version = 1
        var hasMasterPassword: Bool
        var salt: Data?
        var wrappedKey: Data?
        var unmasteredKey: Data?
        var sealedCiphertext: Data
    }

    @discardableResult
    private func writeLegacyVault(_ entries: [PasswordBookEntry], at url: URL,
                                  masterPassword: String? = nil) throws -> (data: Data, key: Data) {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let plaintext = try JSONEncoder().encode(entries)
        let ciphertext = try XCTUnwrap(AES.GCM.seal(plaintext, using: key).combined)
        var store = LegacyStore(hasMasterPassword: masterPassword != nil, sealedCiphertext: ciphertext)
        if let masterPassword {
            let salt = Data(repeating: 7, count: 32)
            let wrapping = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(masterPassword.utf8)),
                                                salt: salt, outputByteCount: 32)
            store.salt = salt
            store.wrappedKey = try XCTUnwrap(AES.GCM.seal(keyData, using: wrapping).combined)
        } else {
            store.unmasteredKey = keyData
        }
        let data = try JSONEncoder().encode(store)
        try data.write(to: url)
        return (data, keyData)
    }

    private func store(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testLockedBookRejectsEntryChangesAndPasswordCandidates() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password", isPreset: true)
            book.setMasterPassword("fixture-master")
            book.lock()
            let originalData = try Data(contentsOf: url)

            book.addEntry(title: "Rejected", password: "rejected-password", isPreset: true)
            var edited = entry
            edited.password = "edited-password"
            book.updateEntry(edited)
            book.markUsed(id: entry.id)
            book.removeEntry(id: entry.id)

            XCTAssertTrue(book.isLocked)
            XCTAssertTrue(book.entries.isEmpty)
            XCTAssertTrue(book.presets.isEmpty)
            XCTAssertTrue(book.candidatePasswords().isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), originalData)
            XCTAssertTrue(book.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(book.entries, [entry])
        }
    }

    func testLockedBookCannotReplaceTheMasterPassword() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            book.lock()
            let originalData = try Data(contentsOf: url)

            book.setMasterPassword("replacement-master")

            XCTAssertTrue(book.isLocked)
            XCTAssertTrue(book.hasMasterPassword)
            XCTAssertEqual(try Data(contentsOf: url), originalData)
            XCTAssertTrue(book.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(book.entries, [entry])
        }
    }

    func testLockedBookCannotRemoveProtection() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            book.lock()
            let originalData = try Data(contentsOf: url)

            book.removeMasterPassword()

            XCTAssertTrue(book.isLocked)
            XCTAssertTrue(book.hasMasterPassword)
            XCTAssertEqual(try Data(contentsOf: url), originalData)
            XCTAssertTrue(book.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(book.entries, [entry])
        }
    }

    func testMalformedExistingStoreIsPreservedAndCannotBeEdited() throws {
        try withTemporaryVault { url in
            let originalData = Data("{damaged-vault-fixture".utf8)
            try originalData.write(to: url)

            let book = makeBook(url)
            XCTAssertTrue(book.isLocked)
            XCTAssertNotNil(book.lastError)
            XCTAssertFalse(book.unlock(withMasterPassword: "anything"))
            book.addEntry(title: "Rejected", password: "rejected-password")
            book.setMasterPassword("replacement-master")
            book.removeMasterPassword()

            XCTAssertTrue(book.entries.isEmpty)
            XCTAssertTrue(book.isLocked)
            XCTAssertEqual(try Data(contentsOf: url), originalData)
        }
    }

    func testDamagedCiphertextIsPreservedAndCannotBeEdited() throws {
        try withTemporaryVault { url in
            let initial = makeBook(url)
            initial.addEntry(title: "Fixture", password: "fixture-password")
            var store = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            store["sealedCiphertext"] = Data(repeating: 0, count: 32).base64EncodedString()
            let originalData = try JSONSerialization.data(withJSONObject: store)
            try originalData.write(to: url)

            let book = makeBook(url)
            book.addEntry(title: "Rejected", password: "rejected-password")

            XCTAssertTrue(book.isLocked)
            XCTAssertTrue(book.entries.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), originalData)
        }
    }

    func testUnsupportedStoreVersionIsPreserved() throws {
        try withTemporaryVault { url in
            let initial = makeBook(url)
            initial.addEntry(title: "Fixture", password: "fixture-password")
            var store = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            store["version"] = 99
            let originalData = try JSONSerialization.data(withJSONObject: store)
            try originalData.write(to: url)

            let book = makeBook(url)
            book.addEntry(title: "Rejected", password: "rejected-password")

            XCTAssertTrue(book.isLocked)
            XCTAssertTrue(book.entries.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), originalData)
        }
    }

    func testFailedEntryWritesLeaveMemoryAndDiskUnchanged() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            let originalData = try Data(contentsOf: url)

            try withUnavailableParent(of: url) {
                book.addEntry(title: "Rejected", password: "rejected-password")
                XCTAssertNotNil(book.lastError)
                XCTAssertEqual(book.entries, [entry])
                var edited = entry
                edited.password = "edited-password"
                book.updateEntry(edited)
                XCTAssertEqual(book.entries, [entry])
                book.markUsed(id: entry.id)
                XCTAssertEqual(book.entries, [entry])
                book.removeEntry(id: entry.id)
                XCTAssertEqual(book.entries, [entry])
            }

            XCTAssertEqual(try Data(contentsOf: url), originalData)
            XCTAssertEqual(makeBook(url).entries, [entry])
            book.markUsed(id: entry.id)
            XCTAssertNil(book.lastError)
            XCTAssertNotNil(makeBook(url).entries.first?.lastUsedAt)
        }
    }

    func testFailedProtectionWriteDoesNotPublishProtection() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            let originalKeyIDs = Set(keyStore.savedKeys.keys)

            try withUnavailableParent(of: url) {
                book.setMasterPassword("fixture-master")
                XCTAssertNotNil(book.lastError)
                XCTAssertFalse(book.hasMasterPassword)
                XCTAssertFalse(book.isLocked)
                XCTAssertEqual(book.entries, [entry])
                XCTAssertFalse(book.setMasterPassword("fixture-master", allowQuickUnlock: true))
                XCTAssertFalse(book.isQuickUnlockEnabled)
                XCTAssertEqual(Set(keyStore.savedKeys.keys), originalKeyIDs)
            }

            let reloaded = makeBook(url)
            XCTAssertFalse(reloaded.hasMasterPassword)
            XCTAssertEqual(reloaded.entries, [entry])
        }
    }

    func testFailedProtectionRemovalAndResetKeepTheOriginalVault() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            let originalData = try Data(contentsOf: url)

            try withUnavailableParent(of: url) {
                book.removeMasterPassword()
                XCTAssertNotNil(book.lastError)
                XCTAssertTrue(book.hasMasterPassword)
                XCTAssertEqual(book.entries, [entry])
                book.resetAndClearAll()
                XCTAssertNotNil(book.lastError)
                XCTAssertTrue(book.hasMasterPassword)
                XCTAssertEqual(book.entries, [entry])
            }

            XCTAssertEqual(try Data(contentsOf: url), originalData)
            let reloaded = makeBook(url)
            XCTAssertTrue(reloaded.isLocked)
            XCTAssertTrue(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(reloaded.entries, [entry])
        }
    }

    func testMasterPasswordKeepsLeadingAndTrailingWhitespace() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword(" fixture-master \n")

            let reloaded = makeBook(url)
            XCTAssertFalse(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertTrue(reloaded.unlock(withMasterPassword: " fixture-master \n"))
            XCTAssertEqual(reloaded.entries, [entry])
        }
    }

    func testUnlockedBookKeepsItsWrappingKeyWhenTheFileIsRemoved() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            try FileManager.default.removeItem(at: url)
            let second = book.addEntry(title: "Second fixture", password: "second-password")

            let reloaded = makeBook(url)
            XCTAssertTrue(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(reloaded.entries, [second, entry])
        }
    }

    func testMasterPasswordRotationRemovalAndResetSurviveRestart() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            book.setMasterPassword("replacement-master")

            let reloaded = makeBook(url)
            XCTAssertFalse(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertTrue(reloaded.unlock(withMasterPassword: "replacement-master"))
            XCTAssertEqual(reloaded.entries, [entry])
            reloaded.removeMasterPassword()

            let unprotected = makeBook(url)
            XCTAssertFalse(unprotected.hasMasterPassword)
            XCTAssertEqual(unprotected.entries, [entry])
            unprotected.resetAndClearAll()
            let reset = makeBook(url)
            XCTAssertFalse(reset.hasMasterPassword)
            XCTAssertFalse(reset.isLocked)
            XCTAssertTrue(reset.entries.isEmpty)
        }
    }

    func testProtectedCiphertextTamperingDoesNotUnlockOrOverwriteTheVault() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            var store = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let encodedCiphertext = try XCTUnwrap(store["sealedCiphertext"] as? String)
            var ciphertext = try XCTUnwrap(Data(base64Encoded: encodedCiphertext))
            ciphertext[ciphertext.count - 1] ^= 1
            store["sealedCiphertext"] = ciphertext.base64EncodedString()
            let tamperedData = try JSONSerialization.data(withJSONObject: store)
            try tamperedData.write(to: url)

            let reloaded = makeBook(url)
            XCTAssertFalse(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertTrue(reloaded.isLocked)
            XCTAssertTrue(reloaded.entries.isEmpty)
            XCTAssertNotNil(reloaded.lastError)
            XCTAssertEqual(try Data(contentsOf: url), tamperedData)
        }
    }

    func testVaultFilesArePrivateAndMasterProtectionDoesNotStoreTheFileKey() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            let data = try Data(contentsOf: url)
            let store = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(store["unmasteredKey"])
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("fixture-password"))
            let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            XCTAssertEqual(files, [url.lastPathComponent])
        }
    }

    func testUnavailableNewVaultFailsClosedAndCanBeExplicitlyResetAfterRecovery() throws {
        try withTemporaryVault { url in
            var book: PasswordBook!
            try withUnavailableParent(of: url) {
                book = makeBook(url)
                XCTAssertTrue(book.isLocked)
                XCTAssertNotNil(book.lastError)
                book.addEntry(title: "Rejected", password: "rejected-password")
                XCTAssertTrue(book.entries.isEmpty)
            }
            book.resetAndClearAll()
            XCTAssertFalse(book.isLocked)
            XCTAssertNil(book.lastError)
            XCTAssertTrue(makeBook(url).entries.isEmpty)
        }
    }

    func testUnmasteredV2UsesOnlyAnExternalKeyAndMissingKeyDoesNotReplaceTheVault() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            let data = try Data(contentsOf: url)
            let metadata = try store(at: url)
            XCTAssertEqual(metadata["version"] as? Int, 2)
            XCTAssertNil(metadata["unmasteredKey"])
            let keyID = try XCTUnwrap(metadata["keychainKeyID"] as? String)
            let record = try XCTUnwrap(keyStore.savedKeys[keyID])
            XCTAssertEqual(record.key.count, 32)
            XCTAssertFalse(record.requiresUserPresence)
            XCTAssertEqual(makeBook(url).entries, [entry])

            keyStore.shouldFailLoading = true
            let unavailable = makeBook(url)
            XCTAssertTrue(unavailable.isLocked)
            XCTAssertTrue(unavailable.entries.isEmpty)
            XCTAssertNotNil(unavailable.lastError)
            unavailable.addEntry(title: "Rejected", password: "rejected-password")
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    func testKeychainCreationFailureNeverFallsBackToAnInlineKey() throws {
        try withTemporaryVault { url in
            keyStore.shouldFailSaving = true
            let book = makeBook(url)
            XCTAssertTrue(book.isLocked)
            XCTAssertNotNil(book.lastError)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(keyStore.savedKeys.isEmpty)
            keyStore.shouldFailSaving = false
            book.resetAndClearAll()
            XCTAssertFalse(book.isLocked)
            XCTAssertNil(try store(at: url)["unmasteredKey"])
        }
    }

    func testLegacyUnmasteredVaultMigratesAndRotatesItsExposedFileKey() throws {
        try withTemporaryVault { url in
            let entry = PasswordBookEntry(title: "Legacy fixture", password: "fixture-password", isPreset: true)
            let legacy = try writeLegacyVault([entry], at: url)
            let book = makeBook(url)
            XCTAssertEqual(book.entries, [entry])
            XCTAssertNil(book.lastError)
            let metadata = try store(at: url)
            XCTAssertEqual(metadata["version"] as? Int, 2)
            XCTAssertNil(metadata["unmasteredKey"])
            let id = try XCTUnwrap(metadata["keychainKeyID"] as? String)
            XCTAssertNotEqual(keyStore.savedKeys[id]?.key, legacy.key)
            XCTAssertEqual(makeBook(url).entries, [entry])
        }
    }

    func testLegacyMigrationKeychainFailurePreservesEveryOriginalByte() throws {
        try withTemporaryVault { url in
            let entry = PasswordBookEntry(title: "Legacy fixture", password: "fixture-password")
            let legacy = try writeLegacyVault([entry], at: url)
            keyStore.shouldFailSaving = true
            let book = makeBook(url)
            XCTAssertTrue(book.isLocked)
            XCTAssertTrue(book.entries.isEmpty)
            XCTAssertNotNil(book.lastError)
            XCTAssertEqual(try Data(contentsOf: url), legacy.data)
            keyStore.shouldFailSaving = false
            XCTAssertEqual(makeBook(url).entries, [entry])
        }
    }

    func testLegacyMigrationWriteFailureRollsBackItsNewKeyAndKeepsTheOriginalFile() throws {
        try withTemporaryVault { url in
            let entry = PasswordBookEntry(title: "Legacy fixture", password: "fixture-password")
            let legacy = try writeLegacyVault([entry], at: url)
            let parent = url.deletingLastPathComponent()
            let backup = parent.deletingLastPathComponent().appendingPathComponent("saved-vault")
            keyStore.onSave = {
                do {
                    try FileManager.default.moveItem(at: parent, to: backup)
                    try Data("not a directory".utf8).write(to: parent)
                } catch { XCTFail("Could not create the deterministic fixture write failure.") }
            }
            let book = makeBook(url)
            keyStore.onSave = nil
            XCTAssertTrue(book.isLocked)
            XCTAssertNotNil(book.lastError)
            XCTAssertTrue(keyStore.savedKeys.isEmpty)
            XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(url.lastPathComponent)), legacy.data)
            try FileManager.default.removeItem(at: parent)
            try FileManager.default.moveItem(at: backup, to: parent)
            XCTAssertEqual(makeBook(url).entries, [entry])
        }
    }

    func testLegacyMasterUnlockMigratesHKDFToPBKDF2WithoutOptingInToQuickUnlock() throws {
        try withTemporaryVault { url in
            let entry = PasswordBookEntry(title: "Legacy fixture", password: "fixture-password")
            let legacy = try writeLegacyVault([entry], at: url, masterPassword: "fixture-master")
            let book = makeBook(url)
            XCTAssertFalse(book.unlock(withMasterPassword: "incorrect"))
            XCTAssertEqual(try Data(contentsOf: url), legacy.data)
            XCTAssertTrue(book.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(book.entries, [entry])
            let metadata = try store(at: url)
            XCTAssertEqual(metadata["version"] as? Int, 2)
            XCTAssertEqual(metadata["kdfRounds"] as? Int, 600_000)
            XCTAssertNil(metadata["unmasteredKey"])
            XCTAssertNil(metadata["keychainKeyID"])
            XCTAssertNil(metadata["quickUnlockKeyID"])
            XCTAssertTrue(keyStore.savedKeys.isEmpty)
            let portable = PasswordBook(storageURL: url, keyStore: TestPasswordBookKeyStore())
            XCTAssertTrue(portable.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(portable.entries, [entry])
        }
    }

    func testLegacyTrimmedMasterInputMigratesToTheExactEnteredPassword() throws {
        try withTemporaryVault { url in
            let entry = PasswordBookEntry(title: "Legacy fixture", password: "fixture-password")
            try writeLegacyVault([entry], at: url, masterPassword: "fixture-master")
            let book = makeBook(url)
            XCTAssertTrue(book.unlock(withMasterPassword: " fixture-master \n"))
            let reloaded = makeBook(url)
            XCTAssertFalse(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertTrue(reloaded.unlock(withMasterPassword: " fixture-master \n"))
            XCTAssertEqual(reloaded.entries, [entry])
        }
    }

    func testRemovingMasterProtectionRequiresASuccessfulKeychainWrite() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            let original = try Data(contentsOf: url)
            keyStore.shouldFailSaving = true
            book.removeMasterPassword()
            XCTAssertTrue(book.hasMasterPassword)
            XCTAssertEqual(book.entries, [entry])
            XCTAssertNotNil(book.lastError)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertTrue(makeBook(url).unlock(withMasterPassword: "fixture-master"))
        }
    }

    func testQuickUnlockRequiresExplicitOptInDespiteAvailableHardware() async throws {
        try await withTemporaryVaultAsync { url in
            let book = makeBook(url)
            book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            book.lock()
            XCTAssertFalse(book.isQuickUnlockEnabled)
            XCTAssertFalse(book.canUseBiometrics())
            XCTAssertTrue(keyStore.savedKeys.isEmpty)
            let unlocked = await book.authenticateWithBiometrics()
            XCTAssertFalse(unlocked)
            XCTAssertTrue(book.isLocked)
            XCTAssertEqual(keyStore.authenticatedReadCount, 0)
        }
    }

    private func withTemporaryVaultAsync(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prozip-vault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root.appendingPathComponent("password_book.dat"))
    }

    func testQuickUnlockReadsAProtectedKeyAndActuallyDecryptsTheSameVault() async throws {
        try await withTemporaryVaultAsync { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            XCTAssertTrue(book.setMasterPassword("fixture-master", allowQuickUnlock: true))
            XCTAssertTrue(book.isQuickUnlockEnabled)
            XCTAssertEqual(keyStore.savedKeys.count, 1)
            XCTAssertTrue(try XCTUnwrap(keyStore.savedKeys.values.first).requiresUserPresence)
            let reloaded = makeBook(url)
            XCTAssertTrue(reloaded.isLocked)
            XCTAssertTrue(reloaded.canUseBiometrics())
            let unlocked = await reloaded.authenticateWithBiometrics(reason: "Fixture authentication")
            XCTAssertTrue(unlocked)
            XCTAssertEqual(reloaded.entries, [entry])
            XCTAssertFalse(reloaded.isLocked)
            XCTAssertEqual(keyStore.authenticatedReadCount, 1)
        }
    }

    func testCancelledAuthenticationAndAnIncorrectReturnedKeyCannotUnlockTheVault() async throws {
        try await withTemporaryVaultAsync { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            XCTAssertTrue(book.setMasterPassword("fixture-master", allowQuickUnlock: true))
            let reloaded = makeBook(url)
            keyStore.authenticationAllowed = false
            let cancelled = await reloaded.authenticateWithBiometrics()
            XCTAssertFalse(cancelled)
            XCTAssertTrue(reloaded.isLocked)
            XCTAssertTrue(reloaded.entries.isEmpty)
            keyStore.authenticationAllowed = true
            keyStore.authenticatedKeyOverride = Data(repeating: 0, count: 32)
            let wrongKey = await reloaded.authenticateWithBiometrics()
            XCTAssertFalse(wrongKey)
            XCTAssertTrue(reloaded.isLocked)
            XCTAssertTrue(reloaded.entries.isEmpty)
            keyStore.authenticatedKeyOverride = nil
            let correctKey = await reloaded.authenticateWithBiometrics()
            XCTAssertTrue(correctKey)
            XCTAssertEqual(reloaded.entries, [entry])
        }
    }

    func testQuickUnlockOptInFailureLeavesThePreviousVaultUsable() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            let original = try Data(contentsOf: url)
            keyStore.supportsAuthentication = false
            XCTAssertFalse(book.setMasterPassword("replacement-master", allowQuickUnlock: true))
            XCTAssertFalse(book.isQuickUnlockEnabled)
            XCTAssertEqual(book.entries, [entry])
            XCTAssertNotNil(book.lastError)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertTrue(makeBook(url).unlock(withMasterPassword: "fixture-master"))
        }
    }

    func testQuickUnlockCapabilityRequiresTheActualProtectedKeychainItem() async throws {
        try await withTemporaryVaultAsync { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            XCTAssertTrue(book.setMasterPassword("fixture-master", allowQuickUnlock: true))
            let id = try XCTUnwrap(try store(at: url)["quickUnlockKeyID"] as? String)
            try keyStore.removeKey(id: id)
            let reloaded = makeBook(url)
            XCTAssertTrue(reloaded.isQuickUnlockEnabled)
            XCTAssertFalse(reloaded.canUseBiometrics())
            let unavailable = await reloaded.authenticateWithBiometrics()
            XCTAssertFalse(unavailable)
            XCTAssertEqual(keyStore.authenticatedReadCount, 0)
            XCTAssertTrue(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(reloaded.entries, [entry])
        }
    }

    func testLateAuthenticationCannotUndoAnExplicitRelock() async throws {
        try await withTemporaryVaultAsync { url in
            let book = makeBook(url)
            book.addEntry(title: "Fixture", password: "fixture-password")
            XCTAssertTrue(book.setMasterPassword("fixture-master", allowQuickUnlock: true))
            book.lock()
            let started = expectation(description: "Fake protected key read started")
            let gate = DispatchSemaphore(value: 0)
            keyStore.onAuthenticatedRead = {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
            }
            let authentication = Task { await book.authenticateWithBiometrics() }
            await fulfillment(of: [started], timeout: 2)
            book.lock()
            gate.signal()
            let unlocked = await authentication.value
            XCTAssertFalse(unlocked)
            XCTAssertTrue(book.isLocked)
            XCTAssertTrue(book.entries.isEmpty)
        }
    }

    func testLateAuthenticationCannotRestoreEntriesAfterReset() async throws {
        try await withTemporaryVaultAsync { url in
            let book = makeBook(url)
            book.addEntry(title: "Fixture", password: "fixture-password")
            XCTAssertTrue(book.setMasterPassword("fixture-master", allowQuickUnlock: true))
            book.lock()
            let started = expectation(description: "Fake protected key read started")
            let gate = DispatchSemaphore(value: 0)
            keyStore.onAuthenticatedRead = {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
            }
            let authentication = Task { await book.authenticateWithBiometrics() }
            await fulfillment(of: [started], timeout: 2)
            book.resetAndClearAll()
            gate.signal()
            let unlocked = await authentication.value
            XCTAssertFalse(unlocked)
            XCTAssertFalse(book.isLocked)
            XCTAssertFalse(book.hasMasterPassword)
            XCTAssertFalse(book.isQuickUnlockEnabled)
            XCTAssertTrue(book.entries.isEmpty)
            XCTAssertEqual(keyStore.savedKeys.count, 1)
            XCTAssertFalse(try XCTUnwrap(keyStore.savedKeys.values.first).requiresUserPresence)
            XCTAssertTrue(makeBook(url).entries.isEmpty)
        }
    }

    func testRotationMakesAnUndeletedOldQuickUnlockKeyUnableToOpenTheNewVault() async throws {
        try await withTemporaryVaultAsync { url in
            let book = makeBook(url)
            let entry = book.addEntry(title: "Fixture", password: "fixture-password")
            XCTAssertTrue(book.setMasterPassword("fixture-master", allowQuickUnlock: true))
            let oldID = try XCTUnwrap(try store(at: url)["quickUnlockKeyID"] as? String)
            let oldKey = try XCTUnwrap(keyStore.savedKeys[oldID]?.key)
            keyStore.shouldFailRemoving = true
            XCTAssertTrue(book.setMasterPassword("replacement-master", allowQuickUnlock: true))
            XCTAssertNotNil(book.lastError)
            let newID = try XCTUnwrap(try store(at: url)["quickUnlockKeyID"] as? String)
            XCTAssertNotEqual(newID, oldID)
            XCTAssertNotEqual(keyStore.savedKeys[newID]?.key, oldKey)
            let reloaded = makeBook(url)
            keyStore.authenticatedKeyOverride = oldKey
            let oldKeyUnlock = await reloaded.authenticateWithBiometrics()
            XCTAssertFalse(oldKeyUnlock)
            XCTAssertTrue(reloaded.isLocked)
            keyStore.authenticatedKeyOverride = nil
            let newKeyUnlock = await reloaded.authenticateWithBiometrics()
            XCTAssertTrue(newKeyUnlock)
            XCTAssertEqual(reloaded.entries, [entry])
        }
    }

    func testV2AuthenticatesKeyReferencesEvenWhenAReplacementReferenceContainsTheSameKey() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            book.addEntry(title: "Fixture", password: "fixture-password")
            var metadata = try store(at: url)
            let oldID = try XCTUnwrap(metadata["keychainKeyID"] as? String)
            let key = try XCTUnwrap(keyStore.savedKeys[oldID]?.key)
            let forgedID = UUID().uuidString
            try keyStore.saveKey(key, id: forgedID, requiresUserPresence: false)
            metadata["keychainKeyID"] = forgedID
            let forgedData = try JSONSerialization.data(withJSONObject: metadata)
            try forgedData.write(to: url)
            let reloaded = makeBook(url)
            XCTAssertTrue(reloaded.isLocked)
            XCTAssertTrue(reloaded.entries.isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), forgedData)
            reloaded.resetAndClearAll()
            XCTAssertNotNil(keyStore.savedKeys[forgedID])
        }
    }

    func testV2RejectsTamperedPasswordWorkFactorsBeforeUnlocking() throws {
        try withTemporaryVault { url in
            let book = makeBook(url)
            book.addEntry(title: "Fixture", password: "fixture-password")
            book.setMasterPassword("fixture-master")
            var metadata = try store(at: url)
            metadata["kdfRounds"] = 1
            let data = try JSONSerialization.data(withJSONObject: metadata)
            try data.write(to: url)
            let reloaded = makeBook(url)
            XCTAssertTrue(reloaded.isLocked)
            XCTAssertNotNil(reloaded.lastError)
            XCTAssertFalse(reloaded.unlock(withMasterPassword: "fixture-master"))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
}

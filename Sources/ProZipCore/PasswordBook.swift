import Foundation
import Combine
import CryptoKit
import CommonCrypto
import Darwin
import ProZipShared

// MARK: - Password Book Entry (doc/06-密码与密码本.md)

public struct PasswordBookEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var password: String
    public var note: String
    public var isPreset: Bool
    public let createdAt: Date
    public var lastUsedAt: Date?

    /// Convenience alias for note to support UI compatibility
    public var notes: String {
        get { note }
        set { note = newValue }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        password: String,
        note: String = "",
        isPreset: Bool = false,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.password = password
        self.note = note
        self.isPreset = isPreset
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - Password Book Storage Container

private struct EncryptedPasswordBookStore: Codable, Equatable, Sendable {
    var version: Int
    var hasMasterPassword: Bool
    var salt: Data?
    var wrappedKey: Data?
    var unmasteredKey: Data?
    var sealedCiphertext: Data
    var kdfRounds: UInt32?
    var keychainKeyID: String?
    var quickUnlockKeyID: String?

    var keyIDs: [String] { [keychainKeyID, quickUnlockKeyID].compactMap { $0 } }
}

// MARK: - Password Book (Observable & Sendable)

public final class PasswordBook: ObservableObject, @unchecked Sendable {
    public static let shared = PasswordBook()
    private static let passwordRounds: UInt32 = 600_000

    private let lockQueue = NSRecursiveLock()
    private let storageURL: URL
    private let keyStore: any PasswordBookKeyStore

    @Published public private(set) var entries: [PasswordBookEntry] = []
    @Published public private(set) var isLocked: Bool = false
    @Published public private(set) var hasMasterPassword: Bool = false
    @Published public private(set) var isQuickUnlockEnabled: Bool = false
    @Published public private(set) var lastError: String?

    private var activeFileKey: SymmetricKey?
    private var currentStore: EncryptedPasswordBookStore?
    private var authenticatedKeyIDs: [String] = []
    private var stateGeneration = UUID()

    public convenience init(storageURL: URL? = nil) {
        self.init(storageURL: storageURL, keyStore: SystemPasswordBookKeyStore())
    }

    // Tests inject a key store so they never access the user's Keychain or authentication UI.
    init(storageURL: URL? = nil, keyStore: any PasswordBookKeyStore) {
        self.keyStore = keyStore
        if let customURL = storageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageURL = appSupport.appendingPathComponent("org.prozip.ProZip", isDirectory: true)
                .appendingPathComponent("password_book.dat")
        }
        loadFromDisk()
    }

    // MARK: - Disk I/O & Cryptography

    private func loadFromDisk() {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        do {
            let store = try readStore()
            hasMasterPassword = store.hasMasterPassword
            isQuickUnlockEnabled = store.quickUnlockKeyID != nil
            if store.hasMasterPassword {
                currentStore = store
                isLocked = true
                return
            }
            let keyData: Data
            if store.version == 1 {
                keyData = store.unmasteredKey!
            } else {
                keyData = try keyStore.loadKey(id: store.keychainKeyID!, authenticationReason: nil)
            }
            guard keyData.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
            let key = SymmetricKey(data: keyData)
            let decoded = try decryptEntries(in: store, using: key)
            if store.version == 1 {
                // Rotate the legacy cleartext file key before removing it from the file.
                if !replaceVault(decoded, masterPassword: nil, allowQuickUnlock: false) { isLocked = true }
            } else {
                accept(store, entries: decoded, key: key)
            }
        } catch {
            let readError = error as NSError
            if readError.domain == NSCocoaErrorDomain && readError.code == NSFileReadNoSuchFileError {
                if !replaceVault([], masterPassword: nil, allowQuickUnlock: false) { isLocked = true }
            } else {
                isLocked = true
                lastError = "无法读取密码本或访问钥匙串，原文件已保留。"
            }
        }
    }

    private func readStore() throws -> EncryptedPasswordBookStore {
        let store = try JSONDecoder().decode(
            EncryptedPasswordBookStore.self, from: Data(contentsOf: storageURL)
        )
        guard store.version == 1 || store.version == 2 else { throw CocoaError(.fileReadCorruptFile) }
        _ = try AES.GCM.SealedBox(combined: store.sealedCiphertext)
        guard store.keyIDs.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if store.hasMasterPassword {
            guard store.salt?.count == 32, let wrapped = store.wrappedKey,
                  store.unmasteredKey == nil, store.keychainKeyID == nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            _ = try AES.GCM.SealedBox(combined: wrapped)
            if store.version == 1 {
                guard store.kdfRounds == nil, store.quickUnlockKeyID == nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            } else {
                // A fixed versioned work factor prevents an untrusted file requesting unbounded work.
                guard store.kdfRounds == Self.passwordRounds else { throw CocoaError(.fileReadCorruptFile) }
            }
        } else {
            guard store.salt == nil, store.wrappedKey == nil, store.kdfRounds == nil,
                  store.quickUnlockKeyID == nil else { throw CocoaError(.fileReadCorruptFile) }
            if store.version == 1 {
                guard store.unmasteredKey?.count == 32, store.keychainKeyID == nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            } else {
                guard store.unmasteredKey == nil, store.keychainKeyID != nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        }
        return store
    }

    private func authenticatedMetadata(for store: EncryptedPasswordBookStore) throws -> Data {
        guard store.version == 2 else { return Data() }
        var metadata = store
        metadata.sealedCiphertext = Data()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(metadata)
    }

    private func decryptEntries(in store: EncryptedPasswordBookStore, using key: SymmetricKey) throws -> [PasswordBookEntry] {
        let sealed = try AES.GCM.SealedBox(combined: store.sealedCiphertext)
        let plaintext = try AES.GCM.open(sealed, using: key, authenticating: authenticatedMetadata(for: store))
        return try JSONDecoder().decode([PasswordBookEntry].self, from: plaintext)
    }

    private func accept(_ store: EncryptedPasswordBookStore, entries: [PasswordBookEntry], key: SymmetricKey) {
        currentStore = store
        authenticatedKeyIDs = store.keyIDs
        activeFileKey = key
        stateGeneration = UUID()
        hasMasterPassword = store.hasMasterPassword
        isQuickUnlockEnabled = store.quickUnlockKeyID != nil
        self.entries = entries
        isLocked = false
        lastError = nil
    }

    private func saveToDiskLocked(
        _ updatedEntries: [PasswordBookEntry], using key: SymmetricKey, store: EncryptedPasswordBookStore
    ) -> Bool {
        do {
            var updatedStore = store
            let plaintext = try JSONEncoder().encode(updatedEntries)
            let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: authenticatedMetadata(for: store))
            guard let combined = sealed.combined else { throw CocoaError(.fileWriteUnknown) }
            updatedStore.sealedCiphertext = combined
            let data = try JSONEncoder().encode(updatedStore)
            let directory = storageURL.deletingLastPathComponent()
            let temporary = directory.appendingPathComponent(".password-book-\(UUID().uuidString).tmp")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                                  attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            guard rename(temporary.path, storageURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            accept(updatedStore, entries: updatedEntries, key: key)
            return true
        } catch {
            lastError = "无法保存密码本，原有记录和保护设置未更改。"
            return false
        }
    }

    private func wrappingKey(for password: String, salt: Data, version: Int) throws -> SymmetricKey {
        if version == 1 {
            return HKDF<SHA256>.deriveKey(
                inputKeyMaterial: SymmetricKey(data: Data(password.utf8)), salt: salt, outputByteCount: 32
            )
        }
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)
        defer { derived.resetBytes(in: 0..<derived.count) }
        let status = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBytes { resultBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.bindMemory(to: CChar.self).baseAddress,
                        passwordData.count, saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), Self.passwordRounds,
                        resultBytes.bindMemory(to: UInt8.self).baseAddress, 32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CocoaError(.coderInvalidValue) }
        return SymmetricKey(data: derived)
    }

    private func removeKeys(_ ids: [String]) -> Bool {
        var succeeded = true
        for id in ids {
            do { try keyStore.removeKey(id: id) }
            catch { succeeded = false }
        }
        return succeeded
    }

    private func replaceVault(
        _ updatedEntries: [PasswordBookEntry], masterPassword: String?, allowQuickUnlock: Bool
    ) -> Bool {
        // Only authenticated metadata may identify old keys for deletion; a locked/corrupt file cannot.
        let oldIDs = authenticatedKeyIDs
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        var store = EncryptedPasswordBookStore(version: 2, hasMasterPassword: masterPassword != nil,
                                              sealedCiphertext: Data())
        var stagedIDs: [String] = []
        do {
            if let password = masterPassword {
                let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                let wrapping = try wrappingKey(for: password, salt: salt, version: 2)
                guard let wrapped = try AES.GCM.seal(keyData, using: wrapping).combined else {
                    throw CocoaError(.coderInvalidValue)
                }
                store.salt = salt
                store.wrappedKey = wrapped
                store.kdfRounds = Self.passwordRounds
                if allowQuickUnlock {
                    let id = UUID().uuidString
                    do {
                        try keyStore.saveKey(keyData, id: id, requiresUserPresence: true)
                    } catch {
                        lastError = "无法开启快捷解锁，请检查应用签名、钥匙串权限及 Touch ID 或 Apple Watch；原有保护未更改。"
                        return false
                    }
                    stagedIDs.append(id)
                    store.quickUnlockKeyID = id
                }
            } else {
                let id = UUID().uuidString
                try keyStore.saveKey(keyData, id: id, requiresUserPresence: false)
                stagedIDs.append(id)
                store.keychainKeyID = id
            }
            guard saveToDiskLocked(updatedEntries, using: key, store: store) else {
                if !removeKeys(stagedIDs) { lastError = "保存失败，原文件已保留；新增钥匙串项未能清理。" }
                return false
            }
            // Rotation makes undeleted old keys unable to decrypt the new file.
            if !removeKeys(oldIDs) { lastError = "密码本已保存，但旧钥匙串项未能清理。" }
            return true
        } catch {
            let cleaned = removeKeys(stagedIDs)
            lastError = cleaned ? "无法保存密码本或访问钥匙串，原有记录和保护设置未更改。"
                : "保存失败，原文件已保留；新增钥匙串项未能清理。"
            return false
        }
    }

    // MARK: - Master Password Management

    /// Changes protection without enabling a second unlock method implicitly.
    public func setMasterPassword(_ masterPassword: String) {
        _ = setMasterPassword(masterPassword, allowQuickUnlock: false)
    }

    /// Quick unlock is stored only after an explicit opt-in by the caller.
    @discardableResult
    public func setMasterPassword(_ masterPassword: String, allowQuickUnlock: Bool) -> Bool {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard !isLocked, activeFileKey != nil else {
            lastError = "请先解锁密码本。"
            return false
        }
        return replaceVault(entries, masterPassword: masterPassword.isEmpty ? nil : masterPassword,
                            allowQuickUnlock: allowQuickUnlock && !masterPassword.isEmpty)
    }

    public func removeMasterPassword() {
        _ = setMasterPassword("", allowQuickUnlock: false)
    }

    public func unlock(withMasterPassword masterPassword: String) -> Bool {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard hasMasterPassword else {
            guard !isLocked, activeFileKey != nil else {
                lastError = "无法读取密码本或访问钥匙串，原文件已保留。"
                return false
            }
            lastError = nil
            return true
        }
        do {
            let store = try readStore()
            guard store.hasMasterPassword, let salt = store.salt, let wrapped = store.wrappedKey else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let sealedKey = try AES.GCM.SealedBox(combined: wrapped)
            let unwrapped: Data
            do {
                unwrapped = try AES.GCM.open(sealedKey, using: wrappingKey(for: masterPassword, salt: salt, version: store.version))
            } catch {
                let trimmed = masterPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                guard store.version == 1, trimmed != masterPassword else { throw error }
                // Original v1 builds trimmed only while setting the password; accept that legacy input once.
                unwrapped = try AES.GCM.open(sealedKey, using: wrappingKey(for: trimmed, salt: salt, version: 1))
            }
            guard unwrapped.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
            let key = SymmetricKey(data: unwrapped)
            let decoded = try decryptEntries(in: store, using: key)
            if store.version == 1 {
                return replaceVault(decoded, masterPassword: masterPassword, allowQuickUnlock: false)
            }
            accept(store, entries: decoded, key: key)
            return true
        } catch {
            lastError = "主密码错误、密码本已损坏或无法读取原文件。"
            return false
        }
    }

    public func lock() {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        stateGeneration = UUID()
        if hasMasterPassword {
            isLocked = true
            entries = []
            activeFileKey = nil
        }
    }

    public func resetAndClearAll() {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        _ = replaceVault([], masterPassword: nil, allowQuickUnlock: false)
    }

    public func reset() { resetAndClearAll() }

    // MARK: - Keychain-authenticated Quick Unlock

    public func canUseBiometrics() -> Bool {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard isQuickUnlockEnabled, let id = currentStore?.quickUnlockKeyID else { return false }
        return keyStore.containsProtectedKey(id: id) && keyStore.canAuthenticate()
    }

    private struct QuickUnlockRequest: Sendable {
        var store: EncryptedPasswordBookStore
        var generation: UUID
    }

    private func quickUnlockRequest() -> QuickUnlockRequest? {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard isLocked, hasMasterPassword, let store = currentStore, store.quickUnlockKeyID != nil else {
            lastError = "尚未开启密码本快捷解锁。"
            return nil
        }
        guard let id = store.quickUnlockKeyID, keyStore.containsProtectedKey(id: id),
              keyStore.canAuthenticate() else {
            lastError = "当前设备无法使用快捷解锁，请输入主密码。"
            return nil
        }
        guard (try? readStore()) == store else {
            lastError = "密码本文件已更改或无法读取，请重新载入。"
            return nil
        }
        return QuickUnlockRequest(store: store, generation: stateGeneration)
    }

    public func authenticateWithBiometrics(reason: String = "解锁 ProZip 密码本") async -> Bool {
        guard let request = await MainActor.run(body: { quickUnlockRequest() }),
              let id = request.store.quickUnlockKeyID else { return false }
        let keyStore = self.keyStore
        let data = await Task.detached(priority: .userInitiated) {
            try? keyStore.loadKey(id: id, authenticationReason: reason)
        }.value
        return await MainActor.run { completeQuickUnlock(request, keyData: data) }
    }

    private func completeQuickUnlock(_ request: QuickUnlockRequest, keyData: Data?) -> Bool {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        // A late authentication result cannot reopen a reset, changed, or explicitly relocked vault.
        guard stateGeneration == request.generation, isLocked, currentStore == request.store else { return false }
        do {
            guard let keyData, keyData.count == 32, try readStore() == request.store else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let key = SymmetricKey(data: keyData)
            let decoded = try decryptEntries(in: request.store, using: key)
            accept(request.store, entries: decoded, key: key)
            return true
        } catch {
            lastError = "快捷解锁未完成，请使用主密码重试。"
            return false
        }
    }

    // MARK: - CRUD Operations

    @discardableResult
    public func addEntry(title: String, password: String, note: String = "", isPreset: Bool = false) -> PasswordBookEntry {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        let entry = PasswordBookEntry(title: title, password: password, note: note, isPreset: isPreset)
        guard !isLocked, let key = activeFileKey, let store = currentStore else {
            lastError = "请先解锁密码本。"
            return entry
        }
        var updated = entries
        updated.insert(entry, at: 0)
        _ = saveToDiskLocked(updated, using: key, store: store)
        return entry
    }

    public func addEntry(title: String, password: String, notes: String, isPreset: Bool = false) {
        addEntry(title: title, password: password, note: notes, isPreset: isPreset)
    }

    public func updateEntry(_ entry: PasswordBookEntry) {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard !isLocked, let key = activeFileKey, let store = currentStore else {
            lastError = "请先解锁密码本。"
            return
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entries
        updated[index] = entry
        _ = saveToDiskLocked(updated, using: key, store: store)
    }

    public func removeEntry(id: UUID) {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard !isLocked, let key = activeFileKey, let store = currentStore else {
            lastError = "请先解锁密码本。"
            return
        }
        guard entries.contains(where: { $0.id == id }) else { return }
        _ = saveToDiskLocked(entries.filter { $0.id != id }, using: key, store: store)
    }

    public func deleteEntry(id: UUID) { removeEntry(id: id) }

    public func markUsed(id: UUID) {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard !isLocked, let key = activeFileKey, let store = currentStore else {
            lastError = "请先解锁密码本。"
            return
        }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = entries
        updated[index].lastUsedAt = Date()
        _ = saveToDiskLocked(updated, using: key, store: store)
    }

    public func recordUsage(id: UUID) { markUsed(id: id) }

    public var presets: [PasswordBookEntry] {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        return isLocked ? [] : entries.filter { $0.isPreset }
    }

    public func getPresets(onlyActive: Bool = true) -> [PasswordBookEntry] { presets }

    public func candidatePasswords() -> [String] {
        lockQueue.lock()
        defer { lockQueue.unlock() }
        guard !isLocked else { return [] }
        let sorted = entries.sorted { a, b in
            let aDate = a.lastUsedAt ?? .distantPast
            let bDate = b.lastUsedAt ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            if a.isPreset != b.isPreset { return a.isPreset && !b.isPreset }
            return a.createdAt > b.createdAt
        }
        var result: [String] = []
        var seen: Set<String> = []
        for entry in sorted where !entry.password.isEmpty && seen.insert(entry.password).inserted {
            result.append(entry.password)
        }
        return result
    }
}

// MARK: - Archive Password Coordinator (doc/06 & doc/11 section 2)

public actor ArchivePasswordCoordinator {
    public static let shared = ArchivePasswordCoordinator()

    private var urlPasswords: [URL: String] = [:]
    private var groupPasswords: [String: String] = [:]
    public private(set) var lastSuccessfulPassword: String?

    public init() {}

    /// Records a password that successfully unlocked an archive or encryption group.
    public func recordSuccessfulPassword(
        _ password: String,
        for archiveURL: URL,
        groupID: String? = nil,
        saveToPasswordBook: Bool = false,
        passwordBook: PasswordBook = .shared
    ) {
        guard !password.isEmpty else { return }

        lastSuccessfulPassword = password
        urlPasswords[archiveURL] = password

        if let gid = groupID, !gid.isEmpty {
            groupPasswords[gid] = password
        }

        if saveToPasswordBook {
            let title = archiveURL.deletingPathExtension().lastPathComponent
            passwordBook.addEntry(title: title, password: password)
        }
    }

    /// Candidate passwords in prioritized sequence:
    /// 1. Session group password (for matching encryption group)
    /// 2. Session archive password
    /// 3. Last successful password (shared across batch operations)
    /// 4. Password book candidates (if unlocked)
    public func candidatePasswords(
        for archiveURL: URL,
        groupID: String? = nil,
        passwordBook: PasswordBook = .shared
    ) -> [String] {
        var candidates: [String] = []

        if let gid = groupID, let groupPwd = groupPasswords[gid] {
            candidates.append(groupPwd)
        }

        if let urlPwd = urlPasswords[archiveURL] {
            candidates.append(urlPwd)
        }

        if let lastPwd = lastSuccessfulPassword {
            candidates.append(lastPwd)
        }

        if !passwordBook.isLocked {
            candidates.append(contentsOf: passwordBook.candidatePasswords())
        }

        // Deduplicate while strictly maintaining precedence
        var result: [String] = []
        var seen: Set<String> = []
        for pwd in candidates where !seen.contains(pwd) && !pwd.isEmpty {
            seen.insert(pwd)
            result.append(pwd)
        }
        return result
    }

    public func sessionPassword(for archiveURL: URL) -> String? {
        urlPasswords[archiveURL]
    }

    public func sessionPassword(forGroupID groupID: String) -> String? {
        groupPasswords[groupID]
    }

    public func clearSessionPasswords() {
        urlPasswords.removeAll()
        groupPasswords.removeAll()
        lastSuccessfulPassword = nil
    }
}

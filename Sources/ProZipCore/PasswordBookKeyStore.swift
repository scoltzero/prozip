import Foundation
import Security
import LocalAuthentication

protocol PasswordBookKeyStore: Sendable {
    func saveKey(_ key: Data, id: String, requiresUserPresence: Bool) throws
    func loadKey(id: String, authenticationReason: String?) throws -> Data
    func loadLegacyKeyInteractively(id: String) throws -> Data
    func removeKey(id: String) throws
    func containsProtectedKey(id: String) -> Bool
    func canAuthenticate() -> Bool
    var supportsDataProtectionQuickUnlock: Bool { get }
}

extension PasswordBookKeyStore {
    func loadLegacyKeyInteractively(id: String) throws -> Data {
        try loadKey(id: id, authenticationReason: nil)
    }

    var supportsDataProtectionQuickUnlock: Bool {
        canAuthenticate()
    }
}

struct SystemPasswordBookKeyStore: PasswordBookKeyStore {
    private static let service = "org.prozip.ProZip.password-book.v2"
    private static let protectedDescription = "ProZip password book authenticated key"
    private static let legacyLock = NSRecursiveLock()

    private func query(id: String, dataProtection: Bool = true) throws -> [String: Any] {
        guard UUID(uuidString: id) != nil else { throw CocoaError(.validationMissingMandatoryProperty) }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id,
            kSecUseDataProtectionKeychain as String: dataProtection
        ]
    }

    private func authenticationFlags() -> SecAccessControlCreateFlags? {
        let context = LAContext()
        let biometry = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        let companion: Bool
        let companionFlag: SecAccessControlCreateFlags
        if #available(macOS 15.0, *) {
            companion = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithCompanion, error: nil)
            companionFlag = .companion
        } else {
            companion = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithWatch, error: nil)
            companionFlag = .watch
        }
        if biometry && companion { return [.biometryCurrentSet, companionFlag, .or] }
        if biometry { return .biometryCurrentSet }
        return companion ? companionFlag : nil
    }

    func canAuthenticate() -> Bool {
        authenticationFlags() != nil
    }

    var supportsDataProtectionQuickUnlock: Bool {
        Self.hasAppleTeamIdentifier() && canAuthenticate()
    }

    private static func hasAppleTeamIdentifier() -> Bool {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess, let dynamicCode else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String else {
            return false
        }
        return !teamID.isEmpty
    }

    private func withLegacyInteraction<T>(allowed: Bool, _ operation: () throws -> T) throws -> T {
        // Classic Keychain ignores LAContext's interaction flag; serialize the process-wide switch.
        Self.legacyLock.lock()
        defer { Self.legacyLock.unlock() }
        var wasAllowed: DarwinBoolean = false
        var status = SecKeychainGetUserInteractionAllowed(&wasAllowed)
        guard status == errSecSuccess else { throw keychainError(status) }
        status = SecKeychainSetUserInteractionAllowed(allowed)
        guard status == errSecSuccess else { throw keychainError(status) }
        defer { _ = SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue) }
        return try operation()
    }

    private func withoutLegacyInteraction<T>(_ operation: () throws -> T) throws -> T {
        try withLegacyInteraction(allowed: false, operation)
    }

    private func loadLegacyKey(id: String, interactive: Bool) throws -> Data {
        try withLegacyInteraction(allowed: interactive) {
            var legacyQuery = try query(id: id, dataProtection: false)
            legacyQuery[kSecReturnData as String] = true
            legacyQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            var legacyResult: CFTypeRef?
            let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &legacyResult)
            guard legacyStatus == errSecSuccess, let data = legacyResult as? Data, data.count == 32 else {
                throw keychainError(legacyStatus == errSecSuccess ? errSecDecode : legacyStatus)
            }
            return data
        }
    }

    func loadLegacyKeyInteractively(id: String) throws -> Data {
        try loadLegacyKey(id: id, interactive: true)
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    func saveKey(_ key: Data, id: String, requiresUserPresence: Bool) throws {
        guard key.count == 32 else { throw CocoaError(.validationMissingMandatoryProperty) }
        if !requiresUserPresence {
            // The classic generic-password store works for ad-hoc builds without DP entitlements.
            try withoutLegacyInteraction {
                var attributes = try query(id: id, dataProtection: false)
                attributes[kSecValueData as String] = key
                var access: SecAccess?
                let accessStatus = SecAccessCreate("ProZip password book" as CFString, nil, &access)
                guard accessStatus == errSecSuccess, let access else { throw keychainError(accessStatus) }
                attributes[kSecAttrAccess as String] = access
                let status = SecItemAdd(attributes as CFDictionary, nil)
                guard status == errSecSuccess else { throw keychainError(status) }
            }
            return
        }
        var attributes = try query(id: id)
        attributes[kSecValueData as String] = key
        attributes[kSecAttrSynchronizable as String] = false
        attributes[kSecAttrDescription as String] = Self.protectedDescription
        let context = LAContext()
        context.interactionNotAllowed = true
        attributes[kSecUseAuthenticationContext as String] = context
        guard let flags = authenticationFlags() else { throw keychainError(errSecNotAvailable) }
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &accessError
        ) else {
            throw accessError?.takeRetainedValue() as Error? ?? CocoaError(.featureUnsupported)
        }
        attributes[kSecAttrAccessControl as String] = access
        // IDs are new for each key: never replace a key still referenced by the current file.
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw keychainError(status)
        }
    }

    func loadKey(id: String, authenticationReason: String?) throws -> Data {
        var attributes = try query(id: id)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        if authenticationReason != nil {
            attributes[kSecAttrDescription as String] = Self.protectedDescription
        }
        let context = LAContext()
        context.interactionNotAllowed = authenticationReason == nil
        if let reason = authenticationReason {
            context.localizedReason = reason.isEmpty ? "解锁 ProZip 密码本" : reason
        }
        attributes[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if authenticationReason == nil && (status == errSecItemNotFound || status == errSecMissingEntitlement
                                           || status == errSecNotAvailable) {
            return try loadLegacyKey(id: id, interactive: false)
        }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw keychainError(status == errSecSuccess ? errSecDecode : status)
        }
        return data
    }

    func containsProtectedKey(id: String) -> Bool {
        guard var attributes = try? query(id: id) else { return false }
        attributes[kSecAttrDescription as String] = Self.protectedDescription
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        attributes[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let metadata = result as? [String: Any] else { return false }
        return metadata[kSecAttrAccessControl as String] != nil
    }

    func removeKey(id: String) throws {
        var attributes = try query(id: id)
        let context = LAContext()
        context.interactionNotAllowed = true
        attributes[kSecUseAuthenticationContext as String] = context
        let status = SecItemDelete(attributes as CFDictionary)
        let legacyStatus = try withoutLegacyInteraction {
            SecItemDelete(try query(id: id, dataProtection: false) as CFDictionary)
        }
        guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
            throw keychainError(legacyStatus)
        }
        guard status == errSecSuccess || status == errSecItemNotFound
                || status == errSecMissingEntitlement || status == errSecNotAvailable else {
            throw keychainError(status)
        }
    }
}

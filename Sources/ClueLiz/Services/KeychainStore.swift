import Foundation
import Security

enum APIKeyName: String, CaseIterable {
    case deepgram, gemini, anthropic

    var displayName: String {
        switch self {
        case .deepgram: return "Deepgram (transcription)"
        case .gemini: return "Gemini (live insights)"
        case .anthropic: return "Anthropic (summaries)"
        }
    }
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

extension Notification.Name {
    /// Posted after an API key is saved or deleted — lets AppState re-read key
    /// availability so disabled buttons enable without a restart.
    static let apiKeysChanged = Notification.Name("com.clueliz.apiKeysChanged")
}

/// Generic-password Keychain storage for the three API keys.
///
/// Reads fall back to (and migrate from) the pre-rename service name and the
/// `.env` backup file; writes mirror the key into the `.env` file so it can
/// be restored without retyping.
enum KeychainStore {
    private static let service = "com.clueliz.app"
    /// Service name used before the app was renamed from Clueless.
    private static let legacyService = "com.clueless.app"

    private static func baseQuery(service: String, key: APIKeyName) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    static func set(_ value: String, for key: APIKeyName, persistToEnv: Bool = true) throws {
        let data = Data(value.utf8)
        var query = baseQuery(service: service, key: key)

        let updateStatus = SecItemUpdate(query as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        if persistToEnv { EnvKeyFile.write(value, for: key) }
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }

    static func get(_ key: APIKeyName) -> String? {
        if let value = copy(service: service, key: key) { return value }
        // Recover keys saved before the rename, then under the new service.
        if let legacy = copy(service: legacyService, key: key) {
            try? set(legacy, for: key)
            return legacy
        }
        if let fromEnv = EnvKeyFile.value(for: key) {
            try? set(fromEnv, for: key, persistToEnv: false)
            return fromEnv
        }
        return nil
    }

    static func delete(_ key: APIKeyName) throws {
        for service in [service, legacyService] {
            let status = SecItemDelete(baseQuery(service: service, key: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unexpectedStatus(status)
            }
        }
        EnvKeyFile.write(nil, for: key)
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }

    private static func copy(service: String, key: APIKeyName) -> String? {
        var query = baseQuery(service: service, key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

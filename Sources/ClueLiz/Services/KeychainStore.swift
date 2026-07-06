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
enum KeychainStore {
    private static let service = "com.clueliz.app"

    private static func baseQuery(for key: APIKeyName) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    static func set(_ value: String, for key: APIKeyName) throws {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)

        let updateStatus = SecItemUpdate(query as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }

    static func get(_ key: APIKeyName) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(_ key: APIKeyName) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
        NotificationCenter.default.post(name: .apiKeysChanged, object: nil)
    }
}

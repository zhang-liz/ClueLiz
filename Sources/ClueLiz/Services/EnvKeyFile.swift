import Foundation
import ClueLizCore

extension APIKeyName {
    /// Accepted .env variable names; the first is canonical and used for writes.
    var envAliases: [String] {
        switch self {
        case .deepgram: return ["DEEPGRAM_API_KEY", "deepgram-api-key"]
        case .gemini: return ["GEMINI_API_KEY", "gemini-api-key"]
        case .anthropic: return ["ANTHROPIC_API_KEY", "anthropic-api-key", "CLAUDE_API_KEY", "claude-api-key"]
        }
    }
}

/// Plain-text `.env` backup of the API keys, so keys survive Keychain resets
/// and can be provided up front without retyping them in the UI.
///
/// Canonical location: `~/Library/Application Support/ClueLiz/.env`. A `.env`
/// in the process working directory is also read (useful for `swift run` from
/// a checkout) but never written.
enum EnvKeyFile {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClueLiz", isDirectory: true)
            .appendingPathComponent(".env", isDirectory: false)
    }

    private static var readURLs: [URL] {
        [fileURL, URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")]
    }

    /// First value found for `key` across the canonical file then the cwd file.
    static func value(for key: APIKeyName) -> String? {
        for url in readURLs {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let values = EnvFile.parse(text)
            for alias in key.envAliases {
                if let value = values[alias], !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// Imports .env values into the Keychain at launch. The .env file wins:
    /// an edited value replaces whatever the Keychain holds.
    static func syncIntoKeychain() {
        for key in APIKeyName.allCases {
            guard let value = value(for: key), value != KeychainStore.get(key) else { continue }
            try? KeychainStore.set(value, for: key, persistToEnv: false)
        }
    }

    /// Writes (or removes, when nil) a key in the canonical .env file with
    /// owner-only permissions. Alias spellings are removed so a stale alias
    /// can't shadow the update on the next launch.
    static func write(_ value: String?, for key: APIKeyName) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        for alias in key.envAliases.dropFirst() {
            text = EnvFile.updating(text, key: alias, value: nil)
        }
        text = EnvFile.updating(text, key: key.envAliases[0], value: value)

        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

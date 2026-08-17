import Foundation
import Security

/// The user's own Anthropic API key, for the bring-your-own-key path.
///
/// An API key is spendable money, so unlike the rest of `user_settings` this one
/// is deliberately *never* written to Postgres. It lives only in this device's
/// Keychain and is handed to our own API as a per-request `X-Anthropic-Key`
/// header when a BYOK user asks for a summary. A breach of the database — or a
/// leaked service_role key, or an old backup — therefore exposes no user keys,
/// and the server holds the value only for the life of one request.
///
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` keeps the item out of iCloud
/// Keychain and out of device backups: the key never leaves this phone. The cost
/// is that a second device needs the key pasted again. Swapping that constant
/// for `kSecAttrAccessibleAfterFirstUnlock` plus `kSecAttrSynchronizable` would
/// trade the strictness for iCloud sync, and is the only change needed.
enum AnthropicKeyStore {
    private static let service = "com.jonchambers.recap.anthropic-key"

    struct KeyError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Catches paste slips — a truncated key, or some other secret entirely —
    /// before they become a confusing 401 halfway through generating a summary.
    static func isPlausible(_ key: String) -> Bool {
        key.hasPrefix("sk-ant-")
            && key.count >= 20
            && !key.contains(where: \.isWhitespace)
    }

    /// Stores (or replaces) the signed-in user's key.
    static func save(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlausible(trimmed) else {
            throw KeyError(message: "That doesn't look like an Anthropic API key. Keys start with \"sk-ant-\".")
        }

        var query = try await baseQuery()
        // Replace rather than update: a delete-then-add is one code path for both
        // "first key" and "pasted a new one", and can't leave a stale value behind.
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyError(message: "Could not save the key to this device's Keychain (\(status)).")
        }
    }

    /// The stored key, or nil when the user is on platform credits instead.
    static func load() async throws -> String? {
        var query = try await baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            throw KeyError(message: "Could not read the key from this device's Keychain (\(status)).")
        }
        return key
    }

    /// Whether a key is stored, without pulling the secret into memory. Settings
    /// only needs to render "Set" / "Not set", so it should never hold the value.
    static func isSet() async throws -> Bool {
        let query = try await baseQuery()
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the key. Call before signing out, while the user id still resolves.
    static func clear() async throws {
        let query = try await baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyError(message: "Could not remove the key from this device's Keychain (\(status)).")
        }
    }

    /// Scoped to the user id so signing in as a different account on a shared
    /// device can never surface the previous account's key.
    private static func baseQuery() async throws -> [String: Any] {
        let userId = try await StorageService.currentUserId()
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId.uuidString,
        ]
    }
}

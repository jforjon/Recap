import Foundation
import Security

/// The user's own Anthropic API key, for the bring-your-own-key path.
///
/// An API key is spendable money, so it is deliberately kept out of the synced
/// store. It lives only in this device's Keychain and is sent straight to
/// Anthropic by `AnthropicClient` — no server of ours ever sees it.
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

    /// Stores (or replaces) the key.
    static func save(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlausible(trimmed) else {
            throw KeyError(message: "That doesn't look like an Anthropic API key. Keys start with \"sk-ant-\".")
        }

        var query = baseQuery()
        // Replace rather than update: a delete-then-add is one code path for both
        // "first key" and "pasted a new one", and can't leave a stale value behind.
        // The delete matches every account, so it also sweeps up a legacy item.
        SecItemDelete(query as CFDictionary)
        query[kSecAttrAccount as String] = account
        query[kSecValueData as String] = Data(trimmed.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyError(message: "Could not save the key to this device's Keychain (\(status)).")
        }
    }

    /// The stored key, or nil when none has been set.
    static func load() async throws -> String? {
        var query = baseQuery()
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
        #if DEBUG
        if DemoMode.isOn { return true }
        #endif
        let query = baseQuery()
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the key.
    static func clear() async throws {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyError(message: "Could not remove the key from this device's Keychain (\(status)).")
        }
    }

    /// With no accounts there is one key per device, saved under a fixed
    /// account name. Lookups match on the service alone, so a key saved by an
    /// earlier build — under the Supabase user id it was scoped to then — is
    /// still found, and is replaced or cleared along with it.
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    private static let account = "default"
}

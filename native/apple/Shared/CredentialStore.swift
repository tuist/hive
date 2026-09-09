import Foundation
import Security

struct CredentialStore {
    private let service = "dev.tuist.hive.oauth"
    private let account = "current-session"
    private let userDefaultsKey = "dev.tuist.hive.oauth.session-fallback"

    func load() throws -> OAuthSession? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(returningData: true) as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return loadFallback()
        }
        if status == errSecMissingEntitlement {
            return loadFallback()
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError(status: status)
        }
        return try JSONDecoder().decode(OAuthSession.self, from: data)
    }

    func save(_ session: OAuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(
            query(returningData: false) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        if status == errSecItemNotFound {
            var attributes = query(returningData: false)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            if addStatus == errSecMissingEntitlement {
                saveFallback(data)
                return
            }
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError(status: addStatus)
            }
        } else if status == errSecMissingEntitlement {
            saveFallback(data)
        } else if status != errSecSuccess {
            throw CredentialStoreError(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(query(returningData: false) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        guard status == errSecSuccess || status == errSecItemNotFound
                || status == errSecMissingEntitlement else {
            throw CredentialStoreError(status: status)
        }
    }

    // Fallback path for simulator or unsigned builds without a Keychain
    // access group entitlement. Sessions kept here are still sandboxed to
    // the app; production builds with the entitlement never hit this path.
    private func saveFallback(_ data: Data) {
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadFallback() -> OAuthSession? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(OAuthSession.self, from: data)
    }

    private func query(returningData: Bool) -> [String: Any] {
        var value: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if returningData {
            value[kSecReturnData as String] = true
            value[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return value
    }
}

struct CredentialStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "The secure session could not be stored."
    }
}

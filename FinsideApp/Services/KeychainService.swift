import Foundation
import Security

enum KeychainService {
    private static let service = "kz.finside.app"

    enum Key: String {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case pinHash = "pin_hash"
    }

    // MARK: - Save

    @discardableResult
    static func save(key: Key, value: String) -> Bool {
        let data = Data(value.utf8)
        delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let ok = SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        if ok, key == .accessToken {
            AppGroupTokenStore.saveAccessTokenForShareExtension(value)
        }
        return ok
    }

    // MARK: - Read

    static func read(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    @discardableResult
    static func delete(key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Helpers

    static var hasTokens: Bool {
        read(key: .accessToken) != nil && read(key: .refreshToken) != nil
    }

    static var hasPin: Bool {
        read(key: .pinHash) != nil
    }

    static func clearAll() {
        delete(key: .accessToken)
        delete(key: .refreshToken)
        delete(key: .pinHash)
        AppGroupTokenStore.clearAccessTokenForShareExtension()
    }

    /// После обновления приложения токен уже в Keychain — копируем в App Group для Share Extension.
    static func syncAccessTokenToAppGroupIfNeeded() {
        guard let t = read(key: .accessToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty
        else { return }
        AppGroupTokenStore.saveAccessTokenForShareExtension(t)
    }
}

import Foundation

/// Дублирует access token в App Group, чтобы Share Extension мог вызвать API без общего keychain access group.
enum AppGroupTokenStore {
    static let suiteName = "group.kz.finside.app"
    private static let accessKey = "shared_access_token"

    static func saveAccessTokenForShareExtension(_ token: String) {
        UserDefaults(suiteName: suiteName)?.set(token, forKey: accessKey)
    }

    static func clearAccessTokenForShareExtension() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: accessKey)
    }
}

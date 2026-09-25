import Foundation

/// Дублирует access token в App Group, чтобы Share Extension мог вызвать API без общего keychain access group.
enum AppGroupTokenStore {
    static let suiteName = "group.kz.finside.app.shared"
    private static let accessKey = "shared_access_token"

    static func saveAccessTokenForShareExtension(_ token: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(token, forKey: accessKey)
        defaults.synchronize()
    }

    static func clearAccessTokenForShareExtension() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: accessKey)
        defaults.synchronize()
    }
}

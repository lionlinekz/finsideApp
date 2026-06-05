import Foundation

/// Share Extension записывает сюда `conversation_id` после импорта; приложение при активации
/// открывает чат, если переход по `finside://` не успел сработать.
enum ShareImportPendingNavigation {
    static let userDefaultsKey = "pending_share_open_conversation_id"

    static func clear() {
        UserDefaults(suiteName: AppGroupTokenStore.suiteName)?.removeObject(forKey: userDefaultsKey)
    }

    /// Снимает флаг и возвращает id, если он был записан расширением.
    static func consumeConversationIdIfPresent() -> Int? {
        let d = UserDefaults(suiteName: AppGroupTokenStore.suiteName)
        let v = d?.integer(forKey: userDefaultsKey) ?? 0
        guard v > 0 else { return nil }
        d?.removeObject(forKey: userDefaultsKey)
        return v
    }
}

import Foundation

/// REST API base (path prefix `/api` is appended by callers).
///
/// Если на устройстве ошибка TLS («secure connection failed»), это не URL в коде, а доверие к сертификату:
/// на `finside.pro` должен отдаваться **полный chain** (leaf + промежуточные, например `fullchain.pem` для Let’s Encrypt).
/// На корпоративном Wi‑Fi Fortinet/прокси может подменять сертификат — iPhone тогда не доверяет без профиля организации;
/// проверьте с мобильного интернета или https://www.ssllabs.com/ssltest/
enum BackendEnvironment {
    /// Debug + симулятор → Django на Mac (`127.0.0.1` на симуляторе = хост Mac).
    /// Debug + физическое устройство → боевой сервер (на телефоне localhost недоступен).
    /// Release → всегда боевой.
    static var apiBaseURL: String {
        #if DEBUG
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000/api"
        #else
        return "https://finside.pro/api"
        #endif
        #else
        return "https://finside.pro/api"
        #endif
    }

    static var chatWebSocketURL: String {
        #if DEBUG
        #if targetEnvironment(simulator)
        return "ws://127.0.0.1:8000/ws/chat/"
        #else
        return "wss://finside.pro/ws/chat/"
        #endif
        #else
        return "wss://finside.pro/ws/chat/"
        #endif
    }
}

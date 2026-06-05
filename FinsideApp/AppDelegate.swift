import UIKit
import UserNotifications

extension Notification.Name {
    /// Открытие чата после тапа по локальному уведомлению из Share Extension.
    static let finsideOpenConversationFromNotification = Notification.Name("finside.openConversationFromNotification")
    /// APNs прислал/обновил device token. Сервис устройств подхватит и
    /// отправит его на сервер.
    static let finsideApnsTokenUpdated = Notification.Name("finside.apnsTokenUpdated")
}

/// Делегат UIApplication для:
/// 1) тапов по локальным уведомлениям (например «вернуться в Finside» после шаринга);
/// 2) (опционально) регистрации в APNs — включается только если в
///    `FinsideApp.entitlements` присутствует ключ `aps-environment`. На
///    Personal Apple Developer team Apple не разрешает Push Notifications
///    capability, поэтому ключ отсутствует и APNs-блок становится no-op.
///    Чат и согласования продолжают работать через WebSocket, пока
///    приложение открыто.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Bundle identifier, как видит iOS (Info.plist).
    /// Бэкенд используют его в `apns-topic` — должен совпадать, если будет APNs.
    static let bundleIdentifier: String =
        Bundle.main.bundleIdentifier ?? "pro.finside.app"

    /// `true`, если в entitlements есть `aps-environment` (paid Apple Developer
    /// + capability Push Notifications). Считается один раз при старте.
    static let isPushNotificationsEntitled: Bool = {
        guard let url = Bundle.main.url(
            forResource: "FinsideApp", withExtension: "entitlements"
        ) ?? Bundle.main.url(forResource: "Entitlements", withExtension: "plist") else {
            return false
        }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else { return false }
        return plist["aps-environment"] != nil
    }()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Запросить разрешение на уведомления (для локальных бэннеров).
        // Регистрироваться в APNs пытаемся только если есть entitlement —
        // иначе iOS вернёт ошибку «no valid 'aps-environment' entitlement».
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            guard granted, Self.isPushNotificationsEntitled else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    // MARK: - APNs registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        // Сохраняем в keychain, чтобы отправлять на сервер сразу после
        // логина и при каждом обновлении.
        PushTokenStore.save(token: hex)
        NotificationCenter.default.post(
            name: .finsideApnsTokenUpdated,
            object: nil,
            userInfo: ["token": hex]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Часто это симулятор без APNs или отсутствие интернета — не блокируем работу.
        print("[APNs] register failed: \(error.localizedDescription)")
    }

    // MARK: - Foreground presentation

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // MARK: - Notification tap

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let info = response.notification.request.content.userInfo
        let rawId: Int? = {
            if let v = info["conversation_id"] as? Int { return v }
            if let n = info["conversation_id"] as? NSNumber { return n.intValue }
            if let s = info["conversation_id"] as? String { return Int(s) }
            return nil
        }()
        guard let id = rawId, id > 0 else { return }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .finsideOpenConversationFromNotification,
                object: nil,
                userInfo: ["conversationId": id]
            )
        }
    }
}

// MARK: - Push token persistence

/// Хранилище последнего APNs-токена в Keychain. Используем тот же подход,
/// что и для JWT — чтобы токен переживал перезапуск и был доступен
/// сервису устройств сразу после логина.
enum PushTokenStore {
    private static let key = KeychainService.Key.apnsToken

    static func save(token: String) {
        _ = KeychainService.save(key: key, value: token)
    }

    static func read() -> String? {
        KeychainService.read(key: key)
    }

    static func clear() {
        KeychainService.delete(key: key)
    }
}

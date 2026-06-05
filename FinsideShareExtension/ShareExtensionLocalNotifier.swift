import Foundation
import UserNotifications

/// Локальное уведомление после импорта: тап по баннеру открывает приложение «по правилам» iOS, если `finside://` из расширения не сработал.
enum ShareExtensionLocalNotifier {
    private static let requestPrefix = "finside.share.import."

    static func scheduleOpenAppReminder(conversationId: Int?) {
        let center = UNUserNotificationCenter.current()

        let schedule: () -> Void = {
            let content = UNMutableNotificationContent()
            content.title = "Выписка в Finside"
            content.body = "Нажмите, чтобы открыть чат с импортом."
            content.sound = .default
            if let id = conversationId, id > 0 {
                content.userInfo = ["conversation_id": id]
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.6, repeats: false)
            let req = UNNotificationRequest(
                identifier: requestPrefix + UUID().uuidString,
                content: content,
                trigger: trigger
            )
            center.add(req, withCompletionHandler: nil)
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async(execute: schedule)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    DispatchQueue.main.async(execute: schedule)
                }
            default:
                break
            }
        }
    }
}

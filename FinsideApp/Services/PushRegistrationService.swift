import Foundation
import UIKit

/// Связывает APNs device-token и сервер.
/// — Подписывается на `.finsideApnsTokenUpdated` (AppDelegate шлёт это
///   при `didRegisterForRemoteNotificationsWithDeviceToken`).
/// — Подписывается на `.finsideTokensRefreshed` (логин/refresh JWT), чтобы
///   повторить отправку токена, когда пользователь авторизуется.
/// — Помнит последний отправленный токен, чтобы не дёргать сервер впустую.
@MainActor
final class PushRegistrationService {
    static let shared = PushRegistrationService()

    private var lastSentToken: String?
    private var lastSentEnv: String?
    nonisolated(unsafe) private var apnsObserver: NSObjectProtocol?
    nonisolated(unsafe) private var loginObserver: NSObjectProtocol?

    private init() {}

    /// Вызывается из приложения один раз (например, при появлении главного
    /// экрана) — после этого сервис сам следит за APNs/JWT-токенами.
    func start() {
        if apnsObserver == nil {
            apnsObserver = NotificationCenter.default.addObserver(
                forName: .finsideApnsTokenUpdated,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let token = (note.userInfo?["token"] as? String) ?? PushTokenStore.read()
                Task { @MainActor in
                    await self?.syncIfPossible(force: true, overrideToken: token)
                }
            }
        }
        if loginObserver == nil {
            loginObserver = NotificationCenter.default.addObserver(
                forName: .finsideTokensRefreshed,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncIfPossible(force: false)
                }
            }
        }
        Task { @MainActor in
            await syncIfPossible(force: false)
        }
    }

    /// Отправляет APNs-токен на сервер, если есть и JWT, и APNs-токен.
    /// `force=true` шлёт даже если токен совпадает с предыдущим — например,
    /// после смены APNs-токена системой.
    func syncIfPossible(force: Bool, overrideToken: String? = nil) async {
        let token = overrideToken ?? PushTokenStore.read()
        guard let token, !token.isEmpty else { return }
        guard KeychainService.read(key: .accessToken)?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else { return }

        let env = Self.currentEnvironment
        if !force, lastSentToken == token, lastSentEnv == env { return }

        do {
            try await APIService.shared.registerDeviceToken(
                token: token,
                platform: "ios",
                bundleId: AppDelegate.bundleIdentifier,
                environment: env
            )
            lastSentToken = token
            lastSentEnv = env
        } catch {
            // Молча: повторим при следующем логине / событии APNs.
            print("[PushRegistration] failed: \(error.localizedDescription)")
        }
    }

    /// Аккуратно отписать устройство при логауте.
    func unregisterCurrent() async {
        guard let token = PushTokenStore.read(), !token.isEmpty else { return }
        try? await APIService.shared.unregisterDeviceToken(token: token)
        lastSentToken = nil
        lastSentEnv = nil
        PushTokenStore.clear()
    }

    /// `sandbox` для DEBUG-сборок (Xcode → симулятор/устройство), `production`
    /// для App Store/TestFlight. Это влияет на хост APNs у сервера.
    static var currentEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

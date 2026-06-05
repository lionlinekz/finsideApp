import SwiftUI
import UIKit

@main
struct FinsideAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var chatService = ChatService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(chatService)
                .preferredColorScheme(appState.appearancePreference.preferredColorScheme)
                .onAppear {
                    // Токен в App Group нужен Share Extension до входа на главный экран.
                    KeychainService.syncAccessTokenToAppGroupIfNeeded()
                    // Запустить отслеживание APNs/JWT и автоматическую
                    // регистрацию push-токена на сервере.
                    PushRegistrationService.shared.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: .finsideTokensRefreshed)) { _ in
                    KeychainService.syncAccessTokenToAppGroupIfNeeded()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: appState.currentScreen) { _, screen in
                    guard screen == .main,
                          let id = appState.pendingChatOpenConversationId else { return }
                    appState.pendingChatOpenConversationId = nil
                    chatService.navigateToConversation(id: id)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "finside" else { return }

        switch url.host {
        case "chat":
            guard let idStr = url.pathComponents.dropFirst().first,
                  let conversationId = Int(idStr) else {
                chatService.pendingOpenChatsTab = true
                return
            }
            ShareImportPendingNavigation.clear()
            if appState.currentScreen == .main {
                chatService.navigateToConversation(id: conversationId)
            } else {
                appState.pendingChatOpenConversationId = conversationId
            }
        case "chats":
            chatService.pendingOpenChatsTab = true
        default:
            break
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(ChatService.self) private var chatService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .login:
                LoginView()
                    .transition(.opacity)
            case .pinSetup:
                PinSetupView()
                    .transition(.opacity)
            case .lockScreen:
                LockScreenView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.currentScreen)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            scheduleConsumeShareImportPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            scheduleConsumeShareImportPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: .finsideOpenConversationFromNotification)) { note in
            let raw = note.userInfo?["conversationId"]
            let id: Int? = {
                if let i = raw as? Int { return i }
                if let n = raw as? NSNumber { return n.intValue }
                return nil
            }()
            guard let id, id > 0 else { return }
            ShareImportPendingNavigation.clear()
            if appState.currentScreen == .main {
                chatService.navigateToConversation(id: id)
            } else {
                appState.pendingChatOpenConversationId = id
            }
        }
    }

    /// Дожидаемся `onOpenURL` от Share Extension, затем один раз читаем запасной флаг из App Group.
    private func scheduleConsumeShareImportPending() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let id = ShareImportPendingNavigation.consumeConversationIdIfPresent() else { return }
            if appState.currentScreen == .main {
                chatService.navigateToConversation(id: id)
            } else {
                appState.pendingChatOpenConversationId = id
            }
        }
    }
}

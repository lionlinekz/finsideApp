import SwiftUI

@main
struct FinsideAppApp: App {
    @State private var appState = AppState()
    @State private var chatService = ChatService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(chatService)
                .preferredColorScheme(appState.appearancePreference.preferredColorScheme)
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
        guard url.scheme == "finside",
              url.host == "chat",
              let idStr = url.pathComponents.dropFirst().first,
              let conversationId = Int(idStr) else { return }

        if appState.currentScreen == .main {
            chatService.navigateToConversation(id: conversationId)
        } else {
            appState.pendingChatOpenConversationId = conversationId
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

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
    }
}

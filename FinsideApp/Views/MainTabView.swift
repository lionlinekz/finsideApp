import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home
    case chats
    case tasks
    case calendar
    case settings
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .home
    @Environment(ChatService.self) private var chatService

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Главная", systemImage: "house")
                }
                .tag(AppTab.home)

            ChatsView()
                .tabItem {
                    Label("Каналы", systemImage: "message")
                }
                .badge(chatService.totalUnreadCount)
                .tag(AppTab.chats)

            TasksView()
                .tabItem {
                    Label("Задачи", systemImage: "checklist")
                }
                .tag(AppTab.tasks)

            CalendarTabView()
                .tabItem {
                    Label("Календарь", systemImage: "calendar")
                }
                .tag(AppTab.calendar)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .task {
            KeychainService.syncAccessTokenToAppGroupIfNeeded()
            chatService.start()
        }
        .onChange(of: chatService.pendingNavigationConversationId) { _, newId in
            if newId != nil {
                selectedTab = .chats
            }
        }
        .onChange(of: chatService.pendingOpenChatsTab) { _, open in
            guard open else { return }
            selectedTab = .chats
            chatService.pendingOpenChatsTab = false
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
        .environment(ChatService())
}

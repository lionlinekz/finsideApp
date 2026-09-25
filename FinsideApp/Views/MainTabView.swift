import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home
    case chats
    case tasks
    case calendar
    case settings
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: AppTab = .home
    @Environment(ChatService.self) private var chatService

    private var isInitiator: Bool {
        appState.user?.isInitiatorRole ?? false
    }

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

            if !isInitiator {
                TasksView()
                    .tabItem {
                        Label("Заметки", systemImage: "note.text")
                    }
                    .tag(AppTab.tasks)

                CalendarTabView()
                    .tabItem {
                        Label("Календарь", systemImage: "calendar")
                    }
                    .tag(AppTab.calendar)
            }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .onAppear {
            if isInitiator, selectedTab == .tasks || selectedTab == .calendar {
                selectedTab = .home
            }
        }
        .onChange(of: appState.user?.roleCode) { _, _ in
            if isInitiator, selectedTab == .tasks || selectedTab == .calendar {
                selectedTab = .home
            }
        }
        .task {
            KeychainService.syncAccessTokenToAppGroupIfNeeded()
            chatService.start()
        }
        .onAppear {
            if chatService.pendingOpenChatsTab {
                selectedTab = .chats
                chatService.pendingOpenChatsTab = false
            }
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

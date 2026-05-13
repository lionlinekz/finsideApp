import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            List {
                Section {
                    Label("Уведомления", systemImage: "bell")
                }

                Section("Внешний вид") {
                    Picker(selection: $appState.appearancePreference) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.title).tag(pref)
                        }
                    } label: {
                        Label("Тема оформления", systemImage: "circle.lefthalf.filled")
                    }
                }

                Section {
                    Label("Конфиденциальность", systemImage: "lock")
                }

                Section("Бизнес") {
                    NavigationLink {
                        TeamUsersView()
                    } label: {
                        Label("Пользователи", systemImage: "person.3")
                    }
                    NavigationLink {
                        CompanySettingsView()
                    } label: {
                        Label("Компания", systemImage: "building.2.crop.circle")
                    }
                    NavigationLink {
                        BranchesView()
                    } label: {
                        Label("Филиалы", systemImage: "mappin.and.ellipse")
                    }
                    NavigationLink {
                        BankAccountsView()
                    } label: {
                        Label("Банковские счета", systemImage: "building.columns")
                    }
                }

                Section {
                    NavigationLink {
                        HelpSupportView()
                    } label: {
                        Label("Помощь и поддержка", systemImage: "questionmark.circle")
                    }
                    Label("О приложении", systemImage: "info.circle")
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                #if os(iOS) || os(visionOS)
                ToolbarItem(placement: .topBarTrailing) {
                    AvatarMenuButton()
                }
                #else
                ToolbarItem(placement: .automatic) {
                    AvatarMenuButton()
                }
                #endif
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}

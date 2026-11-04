import SwiftUI
import StoreKit

/// Удаление аккаунта внутри приложения (App Store 5.1.1(v)).
struct DeleteAccountView: View {
    @Environment(AppState.self) private var appState
    @State private var showConfirm = false
    @State private var showManageSubscriptions = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        List { Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Аккаунт будет удалён без возможности восстановления.")
                        .font(.headline)
                    if let email = appState.user?.email, !email.isEmpty {
                        Text(email)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Что произойдёт") {
                bullet("Ваш профиль, вход в приложение, чаты и уведомления будут удалены.")
                bullet("Вы будете исключены из всех компаний, в которых состоите.")
                bullet("Если вы единственный участник компании, компания и её данные станут недоступны.")
                bullet("Данные компании, которыми пользуются коллеги, останутся у них.")
            }

            Section {
                Button {
                    showManageSubscriptions = true
                } label: {
                    Label("Управление подпиской", systemImage: "creditcard")
                }
            } header: {
                Text("Подписка")
            } footer: {
                Text("Удаление аккаунта не отменяет подписку в App Store. Отмените её здесь или в настройках Apple ID, чтобы списания прекратились.")
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Label("Удалить аккаунт", systemImage: "person.crop.circle.badge.xmark")
                }
                .disabled(isDeleting)
            }
        }.appListRowBackground() }.appScreenBackground().appListBackground()
        .navigationTitle("Удаление аккаунта")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .confirmationDialog(
            "Удалить аккаунт навсегда?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить аккаунт", role: .destructive) {
                Task { await runDelete() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие нельзя отменить.")
        }
        .overlay {
            if isDeleting {
                ProgressView("Удаление…")
                    .padding(24)
                    .background(AppSurfaceStyle(material: .ultraThinMaterial), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert(
            "Не удалось удалить аккаунт",
            isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.subheadline)
    }

    private func runDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await appState.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

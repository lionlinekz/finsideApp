import SwiftUI

struct HelpSupportView: View {
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var banner: Banner?

    private struct Banner: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    var body: some View {
        List {
            Section {
                Label {
                    Text("По вопросам обучения и работы сервиса пишите в каналы поддержки в приложении или на почту вашего менеджера.")
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Удалить все транзакции", systemImage: "trash")
                }
                .disabled(isDeleting)
            } footer: {
                Text(
                    "Навсегда удаляются все доходы и расходы в организации, а также история импортов банковских выписок. Заявки на оплату, компании и счета не затрагиваются. Действие необратимо."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Помощь и поддержка")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Удалить все транзакции?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить всё", role: .destructive) {
                Task { await runDelete() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это нельзя отменить. Убедитесь, что у вас есть резервная копия данных при необходимости.")
        }
        .overlay {
            if isDeleting {
                ProgressView("Удаление…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert(item: $banner) { item in
            Alert(
                title: Text(item.isError ? "Ошибка" : "Готово"),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func runDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let r = try await APIService.shared.deleteAllTransactionsConfirmed()
            NotificationCenter.default.post(name: .finsideLedgerDidChange, object: nil)
            banner = Banner(
                message:
                    "Удалено операций: доходов \(r.deletedIncomes), расходов \(r.deletedPayments). Загрузок выписок: \(r.deletedStatementUploads).",
                isError: false
            )
        } catch {
            banner = Banner(message: error.localizedDescription, isError: true)
        }
    }
}

#Preview {
    NavigationStack {
        HelpSupportView()
    }
}

import StoreKit
import SwiftUI

/// Выбор тарифа и покупка подписки через App Store.
///
/// Цена показывается из StoreKit (`displayPrice`), а не из нашей базы: она уже
/// в валюте магазина пользователя, и показывать другую App Review не разрешает.
struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @State private var store = StoreKitService.shared

    @State private var plans: [PlanInfo] = []
    @State private var appAccountToken: UUID?
    @State private var selectedProductId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загружаем тарифы…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .background(.background)
            .task { await load() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                if plans.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 12) {
                        ForEach(plans) { plan in
                            PlanCard(
                                plan: plan,
                                product: store.product(for: plan.appleProductId),
                                isSelected: selectedProductId == plan.appleProductId
                            ) {
                                selectedProductId = plan.appleProductId
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }

                if !plans.isEmpty {
                    purchaseButton
                }

                footer
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 8)

            Text("3 дня бесплатно")
                .font(.largeTitle.bold())

            Text("Деньги компании в одном месте: счета, выписки, согласования")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Тарифы пока недоступны")
                .font(.headline)
            Text("Попробуйте позже или напишите в поддержку.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Обновить") {
                Task { await load() }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
    }

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            if store.isPurchasing {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 22)
            } else {
                Text("Начать пробный период")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 22)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .disabled(selectedProduct == nil || store.isPurchasing)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Восстановить покупки")
                }
            }
            .font(.subheadline)
            .disabled(isRestoring)

            Text("Подписка продлевается автоматически, пока её не отменить в настройках Apple ID — не позднее чем за 24 часа до конца текущего периода.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 16) {
                Link("Условия использования", destination: AuthLinks.terms)
                Link("Политика конфиденциальности", destination: AuthLinks.privacy)
            }
            .font(.caption2)

            Button("Выйти") {
                appState.logout()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 36)
    }

    private var selectedProduct: Product? {
        guard let selectedProductId else { return nil }
        return store.product(for: selectedProductId)
    }

    // MARK: - Действия

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await APIService.shared.fetchPlans()
            plans = response.plans
            appAccountToken = response.appAccountToken.flatMap(UUID.init(uuidString:))
            try await store.loadProducts(ids: plans.map(\.appleProductId))
            // Продукт мог не приехать из App Store — выбираем первый доступный.
            selectedProductId = plans.first { store.product(for: $0.appleProductId) != nil }?
                .appleProductId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        errorMessage = nil
        do {
            switch try await store.purchase(product, appAccountToken: appAccountToken) {
            case .success:
                appState.subscriptionActivated()
            case .cancelled:
                break
            case .pending:
                errorMessage = "Покупка ожидает подтверждения. Мы откроем доступ, как только Apple её подтвердит."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }
        do {
            if try await store.restorePurchases() {
                appState.subscriptionActivated()
            } else {
                errorMessage = "Активных покупок на этом Apple ID не найдено."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PlanCard: View {
    let plan: PlanInfo
    let product: Product?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if plan.hasTrial && plan.trialDays > 0 {
                        Text("Первые \(plan.trialDays) \(dayWord(plan.trialDays)) бесплатно")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    if !plan.description.isEmpty {
                        Text(plan.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    if let product {
                        Text(product.displayPrice)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(periodTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("недоступен")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(product == nil)
        .opacity(product == nil ? 0.5 : 1)
    }

    private var periodTitle: String {
        switch plan.billingCycle {
        case "monthly": return "в месяц"
        case "quarterly": return "в квартал"
        case "yearly": return "в год"
        default: return ""
        }
    }

    private func dayWord(_ n: Int) -> String {
        if 11...14 ~= n % 100 { return "дней" }
        switch n % 10 {
        case 1: return "день"
        case 2, 3, 4: return "дня"
        default: return "дней"
        }
    }
}

#Preview {
    PaywallView()
        .environment(AppState())
}

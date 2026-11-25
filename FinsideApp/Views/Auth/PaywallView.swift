import StoreKit
import SwiftUI

/// Выбор тарифа и покупка подписки через App Store.
///
/// Цена показывается из StoreKit (`displayPrice`), а не из нашей базы: она уже
/// в валюте магазина пользователя, и показывать другую App Review не разрешает.
///
/// Пробный период — тоже только из StoreKit (`introductoryOffer`) и только если
/// Apple подтверждает, что пользователь на него имеет право. App Review
/// отклоняет экран, где упомянут триал, которого нет в App Store Connect,
/// и экран, где триал заметнее суммы списания (3.1.2(c)). Поэтому сумма
/// списания здесь — самый крупный элемент, а триал идёт под ней мелко.
struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @State private var store = StoreKitService.shared

    @State private var plans: [PlanInfo] = []
    @State private var appAccountToken: UUID?
    @State private var selectedProductId: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isRestoring = false
    @State private var isActivatingWithoutPurchase = false
    /// Продукты, на пробный период которых у этого Apple ID есть право.
    @State private var trialEligibleProductIds: Set<String> = []

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
            .background(Color.appPlainBackground)
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
                                showsTrial: trialEligibleProductIds.contains(plan.appleProductId),
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

                #if DEBUG
                if !hasPurchasableProduct {
                    debugActivation
                }
                #endif

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

            Text("Подписка Finside")
                .font(.title.bold())

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

    /// Купить нечего: либо сервер не отдал тарифов, либо StoreKit не нашёл
    /// продукты (подписка ещё не заведена в App Store Connect).
    private var hasPurchasableProduct: Bool {
        plans.contains { store.product(for: $0.appleProductId) != nil }
    }

    #if DEBUG
    /// Обход оплаты для отладки. Только в DEBUG-сборках и только если сервер
    /// это разрешил (ALLOW_DEV_SUBSCRIPTION_ACTIVATION). В релиз не попадает.
    ///
    /// Показывается, когда купить нечего — иначе на проде, где у тарифа
    /// заполнен apple_product_id, а продукта в App Store Connect ещё нет,
    /// экран оказывался тупиком: карточка «недоступен» и серая кнопка.
    @ViewBuilder
    private var debugActivation: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.vertical, 16)

            if !plans.isEmpty {
                Text("Продукты не пришли из App Store — подписка ещё не заведена в App Store Connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
            }

            Button {
                Task { await activateWithoutPurchase() }
            } label: {
                if isActivatingWithoutPurchase {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 22)
                } else {
                    Text("Продолжить без тарифа")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isActivatingWithoutPurchase)

            Text("Отладочный режим, в релизе кнопки нет")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 32)
    }
    #endif

    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            if store.isPurchasing {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 22)
            } else {
                Text("Оформить подписку")
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

    /// Право на пробный период решает Apple: оффер должен быть заведён в
    /// App Store Connect, а Apple ID — ещё им не пользоваться.
    private func loadTrialEligibility() async {
        var eligible: Set<String> = []
        for plan in plans {
            guard let product = store.product(for: plan.appleProductId),
                  let subscription = product.subscription,
                  subscription.introductoryOffer?.paymentMode == .freeTrial,
                  await subscription.isEligibleForIntroOffer
            else { continue }
            eligible.insert(plan.appleProductId)
        }
        trialEligibleProductIds = eligible
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

            HStack(spacing: 20) {
                Button("Выйти") {
                    appState.logout()
                }
                .foregroundStyle(.secondary)

                // Удаление доступно и без подписки (App Store 5.1.1(v)).
                NavigationLink("Удалить аккаунт") {
                    DeleteAccountView()
                }
                .foregroundStyle(.red)
            }
            .font(.caption)
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
            await loadTrialEligibility()
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

    #if DEBUG
    /// Включить подписку без оплаты. Сервер откажет, если это не разрешено.
    private func activateWithoutPurchase() async {
        isActivatingWithoutPurchase = true
        errorMessage = nil
        defer { isActivatingWithoutPurchase = false }
        do {
            try await APIService.shared.devActivateSubscription()
            appState.subscriptionActivated()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

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
    /// Показывать пробный период: он заведён в App Store Connect и Apple ID имеет на него право.
    let showsTrial: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let product {
                        // Сумма списания — главный элемент экрана (App Store 3.1.2(c)).
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(product.displayPrice)
                                .font(.title.bold())
                                .foregroundStyle(.primary)
                            Text(periodTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let trialText {
                            Text(trialText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("недоступен")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !plan.description.isEmpty {
                        Text(plan.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(.appSurface, in: .rect(cornerRadius: 14))
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

    /// «Первые 3 дня бесплатно, затем 4 990 ₸ в месяц» — длительность триала
    /// и сумма после него, как требует App Review.
    private var trialText: String? {
        guard showsTrial,
              let product,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else { return nil }
        let length = trialLength(offer.period)
        return "Первые \(length) бесплатно, затем \(product.displayPrice) \(periodTitle)"
    }

    private func trialLength(_ period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day: return "\(n) \(dayWord(n))"
        case .week: return n == 1 ? "7 дней" : "\(n * 7) \(dayWord(n * 7))"
        case .month: return n == 1 ? "месяц" : "\(n) мес."
        case .year: return n == 1 ? "год" : "\(n) г."
        @unknown default: return "\(n) \(dayWord(n))"
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

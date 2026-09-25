import Foundation
import StoreKit

/// Покупка подписки через App Store (StoreKit 2).
///
/// Приложение само никогда не решает, что подписка активна: после удачной
/// покупки оно отдаёт серверу только `transactionId`, а тот проверяет покупку
/// у Apple. Транзакция завершается (`finish()`) лишь после ответа сервера —
/// иначе при обрыве связи оплата потерялась бы.
@MainActor
@Observable
final class StoreKitService {
    static let shared = StoreKitService()

    private(set) var products: [Product] = []
    private(set) var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    private init() {}

    // MARK: - Продукты

    func loadProducts(ids: [String]) async throws {
        guard !ids.isEmpty else {
            products = []
            return
        }
        let loaded = try await Product.products(for: ids)
        // Порядок от StoreKit не гарантирован — держим тот, что задал сервер.
        products = ids.compactMap { id in loaded.first { $0.id == id } }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    // MARK: - Покупка

    enum PurchaseOutcome {
        case success
        case cancelled
        /// «Попросить разрешения» у родителя или ожидание подтверждения оплаты.
        case pending
    }

    func purchase(_ product: Product, appAccountToken: UUID?) async throws -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }

        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken {
            // Единственное, что связывает покупку с пользователем в вебхуке Apple:
            // уведомление приходит без авторизации.
            options.insert(.appAccountToken(appAccountToken))
        }

        let result = try await product.purchase(options: options)

        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            try await confirmWithServer(transaction)
            return .success
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    /// Восстановление покупок. Нужно для App Review и для переустановки приложения.
    func restorePurchases() async throws -> Bool {
        try? await AppStore.sync()

        var restored = false
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(entitlement) else { continue }
            try await confirmWithServer(transaction)
            restored = true
        }
        return restored
    }

    // MARK: - Обновления транзакций

    /// Продления, возвраты и покупки, завершённые вне приложения.
    ///
    /// Запускать при старте приложения. Без этого покупка, подтверждённая
    /// уже после закрытия экрана оплаты, до сервера не дойдёт.
    func startListeningForTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached(priority: .background) {
            for await update in Transaction.updates {
                guard let transaction = try? Self.checkVerified(update) else { continue }
                try? await StoreKitService.shared.confirmWithServer(transaction)
            }
        }
    }

    func stopListeningForTransactions() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: - Внутреннее

    private func confirmWithServer(_ transaction: Transaction) async throws {
        try await APIService.shared.verifyApplePurchase(
            transactionId: String(transaction.id)
        )
        // Только теперь Apple может считать транзакцию обработанной.
        await transaction.finish()
    }

    private nonisolated static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw APIError.serverError("Не удалось проверить покупку в App Store")
        }
    }
}

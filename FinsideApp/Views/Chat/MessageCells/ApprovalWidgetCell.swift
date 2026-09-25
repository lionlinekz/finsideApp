import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct ApprovalWidgetCell: View {
    /// Снапшот сообщения, переданный из родительской ленты. Используется
    /// только для отрисовки статичных полей (сумма, описание, имя
    /// отправителя). Динамические значения — статус согласования и
    /// in-flight маркер — читаем «вживую» из `ChatService`, чтобы
    /// гарантированно обновлять UI после оптимистичного апдейта или
    /// WS-эвента без зависимости от того, перерендерил ли родитель
    /// свой body.
    let message: ChatMessage
    @Environment(ChatService.self) private var chatService
    @Environment(AppState.self) private var appState

    @State private var showReceiptImporter = false
    @State private var receiptError: String?
    @State private var moneySentError: String?

    /// Актуальный статус согласования: берём его из `ChatService`, а если
    /// сообщения по какой-то причине нет в кэше (например, мы открыли
    /// чат из push, а `messagesByConversation` ещё не загружен) — падаем
    /// на статус из снапшота.
    private var liveStatus: ApprovalStatus? {
        if let local = chatService.localApprovalStatuses[message.id] {
            return local
        }
        let live = chatService.messagesByConversation[message.conversationId]?
            .first(where: { $0.id == message.id })?
            .approvalStatus
        return live ?? message.approvalStatus
    }

    private var isPending: Bool {
        liveStatus == .pending
    }

    private var isInFlight: Bool {
        chatService.inFlightApprovals.contains(message.id)
    }

    private var isReceiptUploading: Bool {
        chatService.inFlightReceiptUploads.contains(message.id)
    }

    private var livePayload: MessagePayload {
        chatService.messagesByConversation[message.conversationId]?
            .first(where: { $0.id == message.id })?
            .payload ?? message.payload
    }

    private var liveMoneySent: Bool {
        let live = chatService.messagesByConversation[message.conversationId]?
            .first(where: { $0.id == message.id })?
            .moneySent
        return live ?? message.moneySent ?? false
    }

    private var isMoneySentInFlight: Bool {
        chatService.inFlightMoneySent.contains(message.id)
    }

    private var isPaid: Bool {
        livePayload.paymentId != nil || livePayload.paymentStatus == "paid"
    }

    private var isInitiator: Bool {
        guard let uid = appState.user?.id, let senderId = message.senderId else {
            return false
        }
        return uid == senderId
    }

    private var canAttachReceipt: Bool {
        liveStatus == .approved && isInitiator && !isPaid
    }

    private var canMarkMoneySent: Bool {
        liveStatus == .approved
            && !message.isInvoiceOnly
            && message.conversationId > 0
            && !isInitiator
            && !isPaid
            && !liveMoneySent
    }

    private var canResolveApproval: Bool {
        (appState.user?.canResolveApprovals ?? true) && !isInitiator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(headerTintColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: headerIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(headerTintColor)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Согласование")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                statusBadge
            }

            if let amount = message.payload.amount,
               let money = MoneyAmount(fromString: amount) {
                Text(money.formattedWithCurrency)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.85)
            }

            if let desc = message.payload.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !message.senderName.isEmpty {
                Label(message.senderName, systemImage: "person.crop.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
            }

            if isPending && canResolveApproval {
                HStack(spacing: 10) {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        Task { await chatService.resolveApproval(message: message, newStatus: .approved) }
                    } label: {
                        ZStack {
                            Label("Согласовать", systemImage: "checkmark.circle.fill")
                                .opacity(isInFlight ? 0 : 1)
                            if isInFlight {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isInFlight)

                    Button(role: .destructive) {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        Task { await chatService.resolveApproval(message: message, newStatus: .rejected) }
                    } label: {
                        ZStack {
                            Label("Отклонить", systemImage: "xmark.circle.fill")
                                .opacity(isInFlight ? 0 : 1)
                            if isInFlight {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isInFlight)
                }
                .labelStyle(.titleAndIcon)
                .animation(.easeInOut(duration: 0.2), value: isInFlight)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if isPending && isInitiator {
                Label("Ожидает решения управляющего", systemImage: "clock.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                resolvedFooter
                    .transition(.opacity.combined(with: .move(edge: .top)))

                if canAttachReceipt {
                    receiptAttachSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if canMarkMoneySent {
                    moneySentSection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if isPaid {
                    paidFooter
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            if let receiptError {
                Text(receiptError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let moneySentError {
                Text(moneySentError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(message.formattedTime)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 18)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: liveStatus)
        .animation(.easeInOut(duration: 0.2), value: isPaid)
        .animation(.easeInOut(duration: 0.2), value: liveMoneySent)
        .fileImporter(
            isPresented: $showReceiptImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importReceipt(from: url) }
            case .failure(let err):
                receiptError = err.localizedDescription
            }
        }
    }

    private var receiptAttachSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if liveMoneySent {
                Label("Деньги отправлены — прикрепите квитанцию", systemImage: "paperplane.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("После оплаты прикрепите PDF-квитанцию из Kaspi — сумма проверится автоматически.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                receiptError = nil
                showReceiptImporter = true
            } label: {
                ZStack {
                    Label("Прикрепить квитанцию", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                        .opacity(isReceiptUploading ? 0 : 1)
                    if isReceiptUploading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isReceiptUploading)
        }
    }

    private var moneySentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("После перевода отметьте отправку — инициатор сможет прикрепить квитанцию.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                moneySentError = nil
                Task {
                    let ok = await chatService.markMoneySent(messageId: message.id)
                    if !ok {
                        moneySentError = chatService.error ?? "Не удалось отметить отправку"
                    }
                }
            } label: {
                ZStack {
                    Label("Деньги отправлены", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .opacity(isMoneySentInFlight ? 0 : 1)
                    if isMoneySentInFlight {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isMoneySentInFlight)
        }
    }

    private var paidFooter: some View {
        Label("Оплачено · квитанция учтена", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importReceipt(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent.isEmpty ? "receipt.pdf" : url.lastPathComponent
            let ok = await chatService.attachReceipt(
                messageId: message.id,
                fileData: data,
                fileName: name
            )
            if ok {
                #if canImport(UIKit)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
                receiptError = nil
            } else {
                receiptError = chatService.error ?? "Не удалось прикрепить квитанцию"
            }
        } catch {
            receiptError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let status = liveStatus {
            Text(status.localized)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.14), in: Capsule(style: .continuous))
                .foregroundStyle(statusColor)
        }
    }

    @ViewBuilder
    private var resolvedFooter: some View {
        switch liveStatus {
        case .approved:
            if isPaid {
                Label("Согласовано и оплачено", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isInitiator {
                if liveMoneySent {
                    Label("Деньги отправлены — прикрепите квитанцию", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label("Согласовано — можно оплатить и прикрепить квитанцию", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if liveMoneySent {
                Label("Деньги отправлены, ожидаем квитанцию", systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Запрос согласован", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .rejected:
            Label("Запрос отклонён", systemImage: "xmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    private var statusColor: Color {
        switch liveStatus {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        case nil: return .secondary
        }
    }

    private var headerTintColor: Color {
        switch liveStatus {
        case .approved: return .green
        case .rejected: return .red
        default: return .orange
        }
    }

    private var headerIcon: String {
        switch liveStatus {
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal.fill"
        default: return "banknote.fill"
        }
    }

    private var headerSubtitle: String {
        switch liveStatus {
        case .approved:
            if isPaid { return "Оплачено" }
            if liveMoneySent && !isPaid { return "Деньги отправлены" }
            if isInitiator && canAttachReceipt { return "Ожидает квитанцию" }
            return "Решение принято"
        case .rejected: return "Запрос отклонён"
        default: return "Требуется решение по операции"
        }
    }
}

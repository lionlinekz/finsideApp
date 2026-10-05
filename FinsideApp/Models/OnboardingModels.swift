import Foundation

/// Шаг обязательного онбординга после оплаты: пока не выполнены все задачи,
/// приложение каждый раз открывается на `OnboardingTasksView`, а не на главной.
struct OnboardingTask: Identifiable {
    enum Kind {
        /// Показать модалку с текстом (и, возможно, ссылкой) — выполняется по «Хорошо».
        case acknowledgment
        /// Открыть форму «кто ты»: имя, фамилия, телефон, опциональное селфи.
        case profileForm
    }

    let id: String
    /// Заголовок в списке задач.
    let title: String
    /// Короткая подпись под заголовком в списке.
    let subtitle: String
    /// SF Symbol для значка в списке.
    let icon: String
    let kind: Kind
    let modalTitle: String
    let modalMessage: String
    /// Ссылка, которую можно открыть из модалки `.acknowledgment`. Переход по
    /// ней не обязателен — задача считается выполненной по нажатию «Хорошо»
    /// независимо от этого.
    let linkURL: URL?
    let linkLabel: String?

    static let all: [OnboardingTask] = [
        OnboardingTask(
            id: "telegram_subscribe",
            title: "Подпишитесь на Telegram-канал",
            subtitle: "Новости и обновления Finside",
            icon: "paperplane.fill",
            kind: .acknowledgment,
            modalTitle: "Будьте в курсе",
            modalMessage: "Подпишитесь на канал @finsidepro, чтобы не пропускать новости и обновления Finside.",
            linkURL: AuthLinks.telegram,
            linkLabel: "Открыть канал @finsidepro"
        ),
        OnboardingTask(
            id: "profile_info",
            title: "Расскажите о себе",
            subtitle: "Имя, телефон и фото",
            icon: "person.text.rectangle.fill",
            kind: .profileForm,
            modalTitle: "",
            modalMessage: "",
            linkURL: nil,
            linkLabel: nil
        ),
    ]
}

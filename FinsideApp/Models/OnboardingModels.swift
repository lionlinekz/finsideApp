import Foundation

/// Шаг обязательного онбординга после оплаты: пока не выполнены все задачи,
/// приложение каждый раз открывается на `OnboardingTasksView`, а не на главной.
struct OnboardingTask: Identifiable {
    enum Kind {
        /// Показать модалку с текстом (и, возможно, ссылкой) — выполняется по «Хорошо».
        case acknowledgment
        /// Открыть форму «кто ты»: имя, фамилия, телефон, опциональное селфи.
        case profileForm
        /// Открыть форму «компания»: ИИН/БИН с подтягиванием имени и адреса,
        /// логотип и индустрия.
        case companyForm
        /// Открыть форму «точки»: есть ли физический адрес, и сколько их.
        case pointsForm
        /// Показать необязательные подсказки по продукту (выписка, менеджеры,
        /// категории, правила) со ссылками на YouTube — чисто просветительское,
        /// выполняется по «Хорошо» без каких-либо условий.
        case tips
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
        OnboardingTask(
            id: "company_info",
            title: "Заполните данные компании",
            subtitle: "ИИН/БИН, логотип и индустрия",
            icon: "building.2.fill",
            kind: .companyForm,
            modalTitle: "",
            modalMessage: "",
            linkURL: nil,
            linkLabel: nil
        ),
        OnboardingTask(
            id: "company_points",
            title: "Добавьте точки",
            subtitle: "Физические адреса и филиалы",
            icon: "mappin.and.ellipse",
            kind: .pointsForm,
            modalTitle: "",
            modalMessage: "",
            linkURL: nil,
            linkLabel: nil
        ),
        OnboardingTask(
            id: "product_tips",
            title: "Короткие подсказки по продукту",
            subtitle: "Необязательно — просто чтобы знать, что есть",
            icon: "lightbulb.fill",
            kind: .tips,
            modalTitle: "",
            modalMessage: "",
            linkURL: nil,
            linkLabel: nil
        ),
    ]
}

/// Один пункт необязательных подсказок по продукту (задача `product_tips`).
/// `videoURL` пока `nil` везде — ссылок на YouTube ещё нет, подставить
/// позже, когда появятся ролики.
struct OnboardingTip: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let videoURL: URL?

    static let all: [OnboardingTip] = [
        OnboardingTip(
            id: "statement",
            title: "Как добавить выписку",
            description: "Загрузите банковскую выписку — операции разнесутся по категориям автоматически.",
            icon: "doc.text.magnifyingglass",
            videoURL: nil
        ),
        OnboardingTip(
            id: "managers",
            title: "Как добавить менеджеров",
            description: "Пригласите сотрудников и раздайте им роли и доступы в настройках команды.",
            icon: "person.2.fill",
            videoURL: nil
        ),
        OnboardingTip(
            id: "categories",
            title: "Как настроить категории",
            description: "Создайте свои категории и подкатегории доходов и расходов под ваш бизнес.",
            icon: "square.grid.2x2.fill",
            videoURL: nil
        ),
        OnboardingTip(
            id: "rules",
            title: "Как настроить свои правила",
            description: "Автоматическая категоризация по правилам — чтобы похожие операции размечались сами.",
            icon: "wand.and.stars",
            videoURL: nil
        ),
    ]
}

/// Индустрия компании — фиксированный список для онбординга. На сервере
/// хранится как обычный текст в `Company.direction`, без отдельного enum.
enum CompanyIndustry: String, CaseIterable, Identifiable {
    case retail = "Розничная торговля"
    case wholesale = "Оптовая торговля"
    case horeca = "Общественное питание"
    case construction = "Строительство"
    case logistics = "Транспорт и логистика"
    case it = "IT и технологии"
    case beautyHealth = "Красота и здоровье"
    case services = "Услуги"
    case manufacturing = "Производство"
    case realEstate = "Недвижимость"
    case education = "Образование"
    case entertainment = "Развлечения"
    case agriculture = "Сельское хозяйство"
    case other = "Другое"

    var id: String { rawValue }
}

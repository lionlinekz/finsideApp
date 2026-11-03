import SwiftUI
import UIKit

@main
struct FinsideAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var chatService = ChatService()

    init() {
        // Тёмно-синий фон вместо чёрного во всём приложении (тёмная тема).
        AppBackground.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(chatService)
                .appBackground()
                .preferredColorScheme(appState.appearancePreference.preferredColorScheme)
                .onAppear {
                    // Токен в App Group нужен Share Extension до входа на главный экран.
                    KeychainService.syncAccessTokenToAppGroupIfNeeded()
                    // Запустить отслеживание APNs/JWT и автоматическую
                    // регистрацию push-токена на сервере.
                    PushRegistrationService.shared.start()
                    // Продления и возвраты приходят и вне экрана оплаты —
                    // без этого слушателя такая покупка до сервера не дойдёт.
                    StoreKitService.shared.startListeningForTransactions()
                }
                .onReceive(NotificationCenter.default.publisher(for: .finsideTokensRefreshed)) { _ in
                    KeychainService.syncAccessTokenToAppGroupIfNeeded()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: appState.currentScreen) { _, screen in
                    guard screen == .main,
                          let id = appState.pendingChatOpenConversationId else { return }
                    appState.pendingChatOpenConversationId = nil
                    chatService.navigateToConversation(id: id)
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "finside" else { return }

        switch url.host {
        case "chat":
            guard let idStr = url.pathComponents.dropFirst().first,
                  let conversationId = Int(idStr) else {
                chatService.pendingOpenChatsTab = true
                return
            }
            ShareImportPendingNavigation.clear()
            if appState.currentScreen == .main {
                chatService.navigateToConversation(id: conversationId)
            } else {
                appState.pendingChatOpenConversationId = conversationId
            }
        case "chats":
            chatService.pendingOpenChatsTab = true
        default:
            break
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(ChatService.self) private var chatService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .login:
                LoginView()
                    .transition(.opacity)
            case .signUp:
                SignUpView()
                    .transition(.opacity)
            case .otp(let email):
                OtpVerificationView(email: email)
                    .transition(.opacity)
            case .paywall:
                PaywallView()
                    .transition(.opacity)
            case .pinSetup:
                PinSetupView()
                    .transition(.opacity)
            case .lockScreen:
                LockScreenView()
                    .transition(.opacity)
            case .onboardingTasks:
                OnboardingTasksView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.currentScreen)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appState.appDidEnterBackground()
            case .active:
                appState.appDidBecomeActive()
                scheduleConsumeShareImportPending()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            scheduleConsumeShareImportPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: .finsideOpenConversationFromNotification)) { note in
            let raw = note.userInfo?["conversationId"]
            let id: Int? = {
                if let i = raw as? Int { return i }
                if let n = raw as? NSNumber { return n.intValue }
                return nil
            }()
            guard let id, id > 0 else { return }
            ShareImportPendingNavigation.clear()
            if appState.currentScreen == .main {
                chatService.navigateToConversation(id: id)
            } else {
                appState.pendingChatOpenConversationId = id
            }
        }
    }

    /// Дожидаемся `onOpenURL` от Share Extension, затем один раз читаем запасной флаг из App Group.
    private func scheduleConsumeShareImportPending() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard let id = ShareImportPendingNavigation.consumeConversationIdIfPresent() else { return }
            if appState.currentScreen == .main {
                chatService.navigateToConversation(id: id)
            } else {
                appState.pendingChatOpenConversationId = id
            }
        }
    }
}

// MARK: - App background

/// Тёмная тема в тёмно-синих тонах вместо чёрного/серого. Светлая тема — системная.
///
/// Системные цвета iOS НЕ подменяем: на iOS 26 из них строится Liquid Glass
/// таб-бара, и подмена ломала его (активный таб выглядел выключенным).
/// Вместо этого красим явно: `Color.appBackground`, `.appSurface` и т.д.
enum AppBackground {
    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    // Уровни: фон экрана → карточка → элемент внутри карточки.
    // (base — обычный экран, elevated — лист/поповер, там всё на ступень светлее)
    static let darkBase = rgb(0x050B17)
    static let darkElevated = rgb(0x0A1222)
    static let darkSurface = rgb(0x0F1A2E)
    static let darkSurfaceElevated = rgb(0x16223A)
    static let darkTertiary = rgb(0x172439)
    static let darkTertiaryElevated = rgb(0x1E2D47)
    /// Чуть светлее карточки — плашки «Продажи / Расход», кнопки.
    static let darkRaised = rgb(0x142036)
    /// Таб-бар и навбар на iOS 17–18.
    static let darkChrome = rgb(0x0A1222)

    /// Цвет: в светлой теме `light`, в тёмной — `dark` / `darkElevated` (в листах).
    static func dynamic(light: UIColor, dark: UIColor, darkElevated: UIColor? = nil) -> UIColor {
        UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return light.resolvedColor(with: traits) }
            return traits.userInterfaceLevel == .elevated ? (darkElevated ?? dark) : dark
        }
    }

    static let system = dynamic(light: .systemBackground, dark: darkBase, darkElevated: darkElevated)
    static let grouped = dynamic(light: .systemGroupedBackground, dark: darkBase, darkElevated: darkElevated)
    static let secondaryGrouped = dynamic(light: .secondarySystemGroupedBackground, dark: darkSurface, darkElevated: darkSurfaceElevated)
    static let tertiaryGrouped = dynamic(light: .tertiarySystemGroupedBackground, dark: darkTertiary, darkElevated: darkTertiaryElevated)

    private static var installed = false

    /// Вызвать один раз при запуске, до показа первого экрана.
    static func install() {
        guard !installed else { return }
        installed = true
        // iOS 26+: таб-бар и навбар — системное Liquid Glass, их не настраиваем.
        if #unavailable(iOS 26) {
            configureBars()
        }
    }

    /// iOS 17–18. Таб-бар и навбар: в тёмной теме — тёмно-синие с размытием,
    /// в светлой остаются системными (поверх размытия прозрачный цвет).
    private static func configureBars() {
        let chrome = dynamic(light: .clear, dark: darkChrome.withAlphaComponent(0.88))
        let hairline = dynamic(light: UIColor.black.withAlphaComponent(0.15),
                               dark: UIColor.white.withAlphaComponent(0.08))

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = chrome
        tab.shadowColor = hairline
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Навбар: у верха экрана прозрачный (как раньше), при прокрутке — синий.
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundColor = chrome
        nav.shadowColor = hairline
        let navEdge = UINavigationBarAppearance()
        navEdge.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = navEdge
    }

    /// Фон окна виден за открытым листом (когда экран уменьшается) — красим и его.
    static func paintWindows() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.backgroundColor = system }
        }
    }
}

extension Color {
    /// Фон экранов (вместо `systemGroupedBackground`).
    static var appBackground: Color { Color(uiColor: AppBackground.grouped) }
    /// Фон экранов (вместо `systemBackground` / `.background`).
    static var appPlainBackground: Color { Color(uiColor: AppBackground.system) }
    /// Карточки и поля (вместо `secondarySystemGroupedBackground`).
    static var appSurface: Color { Color(uiColor: AppBackground.secondaryGrouped) }
    /// Элемент внутри карточки (вместо `tertiarySystemGroupedBackground`).
    static var appTertiary: Color { Color(uiColor: AppBackground.tertiaryGrouped) }
}

/// Подложка полей и карточек: в светлой теме — материал (как было),
/// в тёмной — тёмно-синяя поверхность вместо серого стекла.
struct AppSurfaceStyle: ShapeStyle {
    var material: Material = .regularMaterial

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.colorScheme == .dark
            ? AnyShapeStyle(Color.appSurface)
            : AnyShapeStyle(material)
    }
}

extension ShapeStyle where Self == AppSurfaceStyle {
    /// Вместо `.regularMaterial` для полей и карточек.
    static var appSurface: AppSurfaceStyle { AppSurfaceStyle() }
    /// Вместо `.thinMaterial` (пузыри чата и т.п.).
    static var appThinSurface: AppSurfaceStyle { AppSurfaceStyle(material: .thinMaterial) }
}

/// Вешается на корень приложения: тёмно-синий фон под всем приложением.
private struct AppBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .backgroundStyle(Color.appPlainBackground)
            .background(Color.appPlainBackground.ignoresSafeArea())
            .onAppear(perform: AppBackground.paintWindows)
    }
}

/// Фон строк List/Form: в тёмной теме — тёмно-синяя карточка, в светлой — системный.
/// SwiftUI красит строки в обход системных цветов, поэтому задаём явно.
/// Вешать на содержимое списка: `List { Group { … }.appListRowBackground() }`.
private struct AppListRowBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.listRowBackground(colorScheme == .dark ? Color.appSurface : nil)
    }
}

/// Фон под List/Form: в тёмной теме — тёмно-синий вместо системного чёрного.
/// Вешать на сам список: `List { … }.appListBackground()`.
private struct AppListBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .scrollContentBackground(.hidden)
                .background(Color.appBackground.ignoresSafeArea())
        } else {
            content
        }
    }
}

/// Фон экрана, который открывается поверх: пуш в навигации, лист, fullScreenCover.
/// Навигация и листы рисуют свой системный фон (чёрный/серый), поэтому
/// каждому такому экрану задаём фон явно. Вешать на корень `body` экрана.
private struct AppScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appPlainBackground.ignoresSafeArea())
            .presentationBackground(Color.appPlainBackground)
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackgroundModifier()) }
    func appScreenBackground() -> some View { modifier(AppScreenBackgroundModifier()) }
    func appListBackground() -> some View { modifier(AppListBackgroundModifier()) }
    func appListRowBackground() -> some View { modifier(AppListRowBackgroundModifier()) }
}

// MARK: - Toolbar pills (iOS 26)

/// Подложка кнопки в тулбаре. В iOS 26 системное стекло тулбара нельзя
/// перекрасить, поэтому прячем его (`appHideSharedBackground()` на ToolbarItem)
/// и рисуем свою: в тёмной теме — тёмно-синюю, в светлой — материал.
/// На iOS 17–18 ничего не меняет.
private struct AppToolbarPillModifier: ViewModifier {
    var circle: Bool
    var compact: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            let fill = colorScheme == .dark
                ? AnyShapeStyle(Color(uiColor: AppBackground.darkRaised))
                : AnyShapeStyle(.regularMaterial)
            let stroke = Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35)
            if circle {
                content
                    .padding(6)
                    .background(Circle().fill(fill))
                    .overlay(Circle().strokeBorder(stroke, lineWidth: 0.5))
            } else {
                content
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 4 : 9)
                    .background(Capsule().fill(fill))
                    .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.5))
            }
        } else {
            content
        }
    }
}

extension View {
    /// Своя подложка для кнопки в тулбаре (см. `AppToolbarPillModifier`).
    /// `compact` — для пилюли с аватаром внутри (меньше отступы по высоте).
    func appToolbarPill(circle: Bool = false, compact: Bool = false) -> some View {
        modifier(AppToolbarPillModifier(circle: circle, compact: compact))
    }
}

extension ToolbarContent {
    /// iOS 26: убрать системное стекло под кнопкой (её подложку рисует `appToolbarPill`).
    @ToolbarContentBuilder
    func appHideSharedBackground() -> some ToolbarContent {
        if #available(iOS 26, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

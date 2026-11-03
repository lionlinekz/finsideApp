import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home
    case chats
    case tasks
    case calendar
    case settings

    var title: String {
        switch self {
        case .home: "Главная"
        case .chats: "Каналы"
        case .tasks: "Заметки"
        case .calendar: "Календарь"
        case .settings: "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .chats: "message"
        case .tasks: "note.text"
        case .calendar: "calendar"
        case .settings: "gearshape"
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: AppTab = .home
    @Environment(ChatService.self) private var chatService
    private var tabBarVisibility = AppTabBarVisibility.shared

    private var isInitiator: Bool {
        appState.user?.isInitiatorRole ?? false
    }

    private var visibleTabs: [AppTab] {
        isInitiator ? [.home, .chats, .settings] : AppTab.allCases
    }

    var body: some View {
        // Системный таб-бар спрятан: в iOS 26 его стекло нельзя настроить
        // (поверх тёмно-синего оно рисует нейтральный тёмный). Внизу — свой
        // бар на том же Liquid Glass (`AppTabBar`).
        TabView(selection: $selectedTab) {
            HomeView()
                .appTabContent()
                .tag(AppTab.home)

            ChatsView()
                .appTabContent()
                .tag(AppTab.chats)

            if !isInitiator {
                TasksView()
                    .appTabContent()
                    .tag(AppTab.tasks)

                CalendarTabView()
                    .appTabContent()
                    .tag(AppTab.calendar)
            }

            SettingsView()
                .appTabContent()
                .tag(AppTab.settings)
        }
        // Место под бар, чтобы низ списков не прятался под ним.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tabBarVisibility.isHidden {
                Color.clear.frame(height: AppTabBar.height)
            }
        }
        .overlay(alignment: .bottom) {
            if !tabBarVisibility.isHidden {
                AppTabBar(
                    tabs: visibleTabs,
                    selection: $selectedTab,
                    badges: [.chats: chatService.totalUnreadCount]
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tabBarVisibility.isHidden)
        .onAppear {
            if isInitiator, selectedTab == .tasks || selectedTab == .calendar {
                selectedTab = .home
            }
        }
        .onChange(of: appState.user?.roleCode) { _, _ in
            if isInitiator, selectedTab == .tasks || selectedTab == .calendar {
                selectedTab = .home
            }
        }
        .task {
            KeychainService.syncAccessTokenToAppGroupIfNeeded()
            chatService.start()
        }
        .onAppear {
            if chatService.pendingOpenChatsTab {
                selectedTab = .chats
                chatService.pendingOpenChatsTab = false
            }
        }
        .onChange(of: chatService.pendingNavigationConversationId) { _, newId in
            if newId != nil {
                selectedTab = .chats
            }
        }
        .onChange(of: chatService.pendingOpenChatsTab) { _, open in
            guard open else { return }
            selectedTab = .chats
            chatService.pendingOpenChatsTab = false
        }
    }
}

// MARK: - Свой таб-бар

/// Плавающий таб-бар-капсула. На iOS 26 — системный Liquid Glass (`glassEffect`)
/// в прозрачном варианте `.clear` с лёгким синим оттенком: он преломляет фон
/// и не рисует поверх нейтральный тёмный. На iOS 17–18 — размытие + синий.
///
/// Подсветка активного таба — «линза», как в нативном баре iOS 26:
/// при касании она увеличивается и становится стеклом, её можно вести пальцем
/// (иконка под ней увеличивается), при отпускании с пружиной встаёт на таб.
struct AppTabBar: View {
    let tabs: [AppTab]
    @Binding var selection: AppTab
    var badges: [AppTab: Int] = [:]

    /// Высота бара вместе с отступом снизу — столько места оставляем контенту.
    static let height: CGFloat = 70

    @Environment(\.colorScheme) private var colorScheme

    /// Палец на баре.
    @State private var isPressing = false
    /// Центр линзы по X во время касания (в координатах ряда табов).
    @State private var dragX: CGFloat?
    /// Таб под пальцем — для тактильного щелчка при переходе.
    @State private var hoveredTab: AppTab?

    // Настройка вида — крутить здесь.
    /// Оттенок стекла бара в тёмной теме (0 — совсем прозрачное).
    private let darkGlassTint = Color(uiColor: AppBackground.darkRaised).opacity(0.35)
    /// Насколько увеличивается линза при касании.
    private let lensPressScale: CGFloat = 1.28
    /// Увеличение того, что видно сквозь линзу.
    private let lensMagnify: CGFloat = 1.25

    private let barHeight: CGFloat = 62
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let rowWidth = geo.size.width - inset * 2
            let rowHeight = barHeight - inset * 2
            let itemWidth = rowWidth / CGFloat(max(tabs.count, 1))
            let lensX = currentLensX(itemWidth: itemWidth, rowWidth: rowWidth)
            let lensSize = CGSize(width: itemWidth * lensPressScale, height: rowHeight * lensPressScale)
            let lensCenter = CGPoint(x: lensX, y: rowHeight / 2)

            ZStack(alignment: .topLeading) {
                // Подсветка активного таба в покое.
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07))
                    .frame(width: itemWidth, height: rowHeight)
                    .position(lensCenter)
                    .opacity(isPressing ? 0 : 1)

                // Иконки. Пока палец на баре, под линзой их вырезаем —
                // там видна увеличенная копия.
                row(itemWidth: itemWidth, lensX: lensX, inLens: false)
                    .frame(width: rowWidth, height: rowHeight)
                    .mask {
                        Rectangle()
                            .overlay {
                                if isPressing {
                                    Capsule(style: .continuous)
                                        .frame(width: lensSize.width, height: lensSize.height)
                                        .position(lensCenter)
                                        .blendMode(.destinationOut)
                                }
                            }
                            .compositingGroup()
                    }

                // Линза: стекло + увеличенное содержимое под ней.
                if isPressing {
                    lens(size: lensSize, center: lensCenter, rowSize: CGSize(width: rowWidth, height: rowHeight),
                         itemWidth: itemWidth, lensX: lensX)
                        .transition(.scale(scale: 1 / lensPressScale).combined(with: .opacity))
                }
            }
            .frame(width: rowWidth, height: rowHeight)
            .padding(inset)
            .contentShape(Capsule())
            .gesture(dragGesture(itemWidth: itemWidth, rowWidth: rowWidth))
        }
        .frame(height: barHeight)
        .modifier(AppTabBarGlass(darkTint: darkGlassTint))
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: Линза

    private func lens(size: CGSize, center: CGPoint, rowSize: CGSize, itemWidth: CGFloat, lensX: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Тело линзы — стекло.
            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.10))
                .modifier(LensGlass())
                .frame(width: size.width, height: size.height)
                .position(center)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 12, y: 5)

            // Увеличенная копия ряда иконок, видимая только внутри линзы.
            row(itemWidth: itemWidth, lensX: lensX, inLens: true)
                .frame(width: rowSize.width, height: rowSize.height)
                .scaleEffect(lensMagnify, anchor: UnitPoint(x: lensX / rowSize.width, y: 0.5))
                .mask {
                    Capsule(style: .continuous)
                        .frame(width: size.width, height: size.height)
                        .position(center)
                }

            // Ободок с бликом сверху — край стекла.
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.08), Color.white.opacity(0.20)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
                .frame(width: size.width, height: size.height)
                .position(center)
        }
        .frame(width: rowSize.width, height: rowSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func row(itemWidth: CGFloat, lensX: CGFloat, inLens: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                item(tab, itemWidth: itemWidth, lensX: lensX, inLens: inLens)
            }
        }
    }

    private func centerX(of tab: AppTab, itemWidth: CGFloat) -> CGFloat {
        let index = tabs.firstIndex(of: tab) ?? 0
        return itemWidth * (CGFloat(index) + 0.5)
    }

    private func currentLensX(itemWidth: CGFloat, rowWidth: CGFloat) -> CGFloat {
        if let dragX {
            return min(max(dragX, itemWidth / 2), rowWidth - itemWidth / 2)
        }
        return centerX(of: selection, itemWidth: itemWidth)
    }

    private func tab(at x: CGFloat, itemWidth: CGFloat) -> AppTab {
        let index = Int(x / itemWidth)
        return tabs[min(max(index, 0), tabs.count - 1)]
    }

    // MARK: Жест

    private func dragGesture(itemWidth: CGFloat, rowWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                // Координаты жеста — с учётом внутреннего отступа ряда.
                let x = value.location.x - inset
                if !isPressing {
                    hoveredTab = tab(at: x, itemWidth: itemWidth)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                        isPressing = true
                        dragX = x
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
                        dragX = x
                    }
                }
                let hovered = tab(at: x, itemWidth: itemWidth)
                if hovered != hoveredTab {
                    hoveredTab = hovered
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { value in
                let target = tab(at: value.location.x - inset, itemWidth: itemWidth)
                if target != selection {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
                // Пружина с лёгким «перелётом» — как у нативной линзы.
                withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                    selection = target
                    dragX = nil
                    isPressing = false
                }
                hoveredTab = nil
            }
    }

    // MARK: Таб

    private func item(_ tab: AppTab, itemWidth: CGFloat, lensX: CGFloat, inLens: Bool) -> some View {
        let isSelected = tab == selection
        // В линзе акцентом красим таб под пальцем, вне её — выбранный.
        let underLens = abs(centerX(of: tab, itemWidth: itemWidth) - lensX) < itemWidth / 2
        let highlighted = inLens ? underLens : (isSelected && !isPressing)

        return VStack(spacing: 2) {
            Image(systemName: tab.systemImage)
                .symbolVariant(.fill)
                .font(.system(size: 19, weight: .medium))
                .frame(height: 26)
                .overlay(alignment: .topTrailing) { badge(for: tab) }
            Text(tab.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(highlighted ? Color.accentColor : Color.primary.opacity(0.9))
        .frame(width: itemWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityHidden(inLens)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) { selection = tab }
        }
    }

    @ViewBuilder
    private func badge(for tab: AppTab) -> some View {
        if let count = badges[tab], count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(Color.red))
                .offset(x: 12, y: -4)
                .accessibilityLabel("\(count) непрочитанных")
        }
    }
}

/// Тело линзы: на iOS 26 — стекло `.clear`, на старых версиях — тонкий материал.
private struct LensGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.clear, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
    }
}

/// Подложка бара: стекло iOS 26 или размытие на старых версиях.
/// Без `.interactive()`: иначе от касания раздувается весь бар.
private struct AppTabBarGlass: ViewModifier {
    let darkTint: Color
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    colorScheme == .dark ? .clear.tint(darkTint) : .regular,
                    in: .capsule
                )
        } else {
            content
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if colorScheme == .dark {
                                Capsule(style: .continuous)
                                    .fill(Color(uiColor: AppBackground.darkChrome).opacity(0.6))
                            }
                        }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.5), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 14, y: 6)
        }
    }
}

// MARK: - Видимость бара

/// Экраны, где бара быть не должно (например, открытый чат), вешают
/// `.hidesAppTabBar()`; бар прячется, пока такой экран на экране.
@Observable
final class AppTabBarVisibility {
    static let shared = AppTabBarVisibility()
    private var hideCount = 0
    var isHidden: Bool { hideCount > 0 }

    func push() { hideCount += 1 }
    func pop() { hideCount = max(0, hideCount - 1) }
}

private struct HidesAppTabBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { AppTabBarVisibility.shared.push() }
            .onDisappear { AppTabBarVisibility.shared.pop() }
    }
}

extension View {
    /// Спрятать свой таб-бар, пока этот экран открыт.
    func hidesAppTabBar() -> some View { modifier(HidesAppTabBarModifier()) }

    /// Содержимое вкладки: прячем системный таб-бар (рисуем свой).
    fileprivate func appTabContent() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
        .environment(ChatService())
}

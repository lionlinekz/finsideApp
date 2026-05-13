import SwiftUI
import CryptoKit

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    /// `nil` = следовать системной теме
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AuthScreen: Equatable {
    case login
    case pinSetup
    case lockScreen
    case main
}

@MainActor
@Observable
final class AppState {
    private static let appearanceStorageKey = "finside.appearance"
    private static let tasksStorageKey = "finside.task_items.v1"

    var currentScreen: AuthScreen = .login
    /// Deep link из Share Extension, если приложение ещё на экране PIN / логина.
    var pendingChatOpenConversationId: Int?
    var user: UserInfo?
    var isLoading = false
    var errorMessage: String?

    /// Локальные задачи (как во Finpro), сохраняются на устройстве.
    var taskItems: [TaskItem] = []

    var appearancePreference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: Self.appearanceStorageKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.appearanceStorageKey)
        self.appearancePreference = saved.flatMap { AppearancePreference(rawValue: $0) } ?? .system
        loadTasksFromStorage()
        determineInitialScreen()
    }

    func determineInitialScreen() {
        if KeychainService.hasTokens {
            if KeychainService.hasPin {
                currentScreen = .lockScreen
            } else {
                currentScreen = .pinSetup
            }
        } else {
            currentScreen = .login
        }
    }

    // MARK: - Login

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await APIService.shared.login(email: email, password: password)
            user = response.user
            if KeychainService.hasPin {
                currentScreen = .main
            } else {
                currentScreen = .pinSetup
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - PIN

    func setPin(_ pin: String) {
        let hash = SHA256.hash(data: Data(pin.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        KeychainService.save(key: .pinHash, value: hash)
        currentScreen = .main
    }

    func verifyPin(_ pin: String) -> Bool {
        guard let stored = KeychainService.read(key: .pinHash) else { return false }
        let hash = SHA256.hash(data: Data(pin.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return hash == stored
    }

    func unlockWithPin(_ pin: String) {
        if verifyPin(pin) {
            currentScreen = .main
            Task { await refreshAuthenticatedUser() }
        } else {
            errorMessage = "Неверный PIN"
        }
    }

    // MARK: - Biometric

    func unlockWithBiometrics() async {
        let success = await BiometricService.authenticate()
        if success {
            currentScreen = .main
            await refreshAuthenticatedUser()
        }
    }

    /// Обновляет `user` с сервера (аватар и т.д.), если есть сохранённые токены.
    func refreshAuthenticatedUser() async {
        guard KeychainService.hasTokens else { return }
        do {
            user = try await APIService.shared.me()
        } catch {
            // истёк токен — остаёмся без обновления; сеть восстановится при следующем запросе
        }
    }

    // MARK: - Logout

    func logout() {
        KeychainService.clearAll()
        user = nil
        pendingChatOpenConversationId = nil
        taskItems = []
        UserDefaults.standard.removeObject(forKey: Self.tasksStorageKey)
        currentScreen = .login
    }

    // MARK: - Tasks (локально)

    func addUserTask(title: String, deadline: Date?, priority: TaskPriority) {
        let item = TaskItem(
            title: title,
            deadline: deadline,
            createdAt: Date(),
            priority: priority,
            isDone: false,
            origin: .user
        )
        taskItems.insert(item, at: 0)
        persistTasks()
    }

    func toggleTaskDone(id: UUID) {
        guard let i = taskItems.firstIndex(where: { $0.id == id }) else { return }
        taskItems[i].isDone.toggle()
        persistTasks()
    }

    func removeTask(id: UUID) {
        taskItems.removeAll { $0.id == id }
        persistTasks()
    }

    private func loadTasksFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: Self.tasksStorageKey),
              let list = try? JSONDecoder().decode([TaskItem].self, from: data)
        else { return }
        taskItems = list
    }

    private func persistTasks() {
        guard let data = try? JSONEncoder().encode(taskItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.tasksStorageKey)
    }
}

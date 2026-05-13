import Foundation

enum TaskPriority: String, Codable, CaseIterable {
    case high = "Высокий"
    case normal = "Обычный"
}

enum TaskOrigin: String, Codable, CaseIterable {
    case system = "Система"
    case user = "Моя задача"
}

struct TaskItem: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    /// Дедлайн; `nil` — в календаре позиция по `createdAt`.
    var deadline: Date?
    let createdAt: Date
    var priority: TaskPriority
    var isDone: Bool
    var origin: TaskOrigin

    enum CodingKeys: String, CodingKey {
        case id, title, priority, isDone, origin
        case deadline, createdAt
        case due
    }

    init(
        id: UUID = UUID(),
        title: String,
        deadline: Date?,
        createdAt: Date = Date(),
        priority: TaskPriority,
        isDone: Bool,
        origin: TaskOrigin
    ) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.createdAt = createdAt
        self.priority = priority
        self.isDone = isDone
        self.origin = origin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        priority = try c.decode(TaskPriority.self, forKey: .priority)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        origin = try c.decode(TaskOrigin.self, forKey: .origin)

        if let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) {
            createdAt = created
        } else {
            createdAt = try c.decodeIfPresent(Date.self, forKey: .due) ?? Date()
        }

        if let dl = try c.decodeIfPresent(Date.self, forKey: .deadline) {
            deadline = dl
        } else if let legacyDue = try c.decodeIfPresent(Date.self, forKey: .due) {
            deadline = legacyDue
        } else {
            deadline = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(priority, forKey: .priority)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(origin, forKey: .origin)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(deadline, forKey: .deadline)
    }

    /// День для календаря и сортировки (начало суток).
    var calendarPlacementDate: Date {
        Calendar.current.startOfDay(for: deadline ?? createdAt)
    }

    static func dueLabel(deadline: Date?, createdAt: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_KZ")
        f.setLocalizedDateFormatFromTemplate("dMMM")
        if let d = deadline {
            return f.string(from: d)
        }
        return "Без срока · \(f.string(from: createdAt))"
    }

    /// Подзаголовок в календаре.
    var calendarDetailLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        if let d = deadline {
            return "Срок \(f.string(from: d))"
        }
        return "Без срока · создана \(f.string(from: createdAt))"
    }
}

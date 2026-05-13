import Foundation
import SwiftUI

// MARK: - Event Type

enum CalendarEventType: String, Codable, CaseIterable, Identifiable {
    case taxPayment = "tax_payment"
    case plannedPayment = "planned_payment"
    case declaration = "declaration"
    case statReport = "stat_report"
    case nationalBankReport = "national_bank_report"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taxPayment: return "Налоги"
        case .plannedPayment: return "Платежи"
        case .declaration: return "Декларации"
        case .statReport: return "Стат. отчёты"
        case .nationalBankReport: return "Нацбанк"
        }
    }

    var fullLabel: String {
        switch self {
        case .taxPayment: return "Оплата налогов"
        case .plannedPayment: return "Плановый платёж"
        case .declaration: return "Сдача декларации"
        case .statReport: return "Стат. отчётность"
        case .nationalBankReport: return "Отчёт в Нацбанк"
        }
    }

    var icon: String {
        switch self {
        case .taxPayment: return "banknote"
        case .plannedPayment: return "creditcard"
        case .declaration: return "doc.text"
        case .statReport: return "chart.bar.doc.horizontal"
        case .nationalBankReport: return "building.columns"
        }
    }

    var tint: Color {
        switch self {
        case .taxPayment: return .red
        case .plannedPayment: return .blue
        case .declaration: return .orange
        case .statReport: return .purple
        case .nationalBankReport: return .teal
        }
    }
}

// MARK: - Calendar Event

struct CalendarEvent: Codable, Identifiable {
    let id: Int
    let eventType: CalendarEventType
    let title: String
    let description: String
    let dueDate: String
    let amount: String?
    let isRecurring: Bool
    let recurrenceRule: String
    var isCompleted: Bool
    let completedAt: String?
    let isOverdue: Bool
    let daysUntil: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description, amount
        case eventType = "event_type"
        case dueDate = "due_date"
        case isRecurring = "is_recurring"
        case recurrenceRule = "recurrence_rule"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case isOverdue = "is_overdue"
        case daysUntil = "days_until"
    }

    var parsedDueDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dueDate)
    }

    var formattedDueDate: String {
        guard let date = parsedDueDate else { return dueDate }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }

    var formattedAmount: String? {
        guard let amountStr = amount,
              let value = Double(amountStr) else { return nil }
        return DashboardMoney.formatTenge(value)
    }

    var type: CalendarEventType { eventType }
}

// MARK: - API Response

struct CalendarEventsResponse: Codable {
    let events: [CalendarEvent]
    let summary: [String: TypeSummary]
    let datesWithEvents: [String]
    let month: Int
    let year: Int

    enum CodingKeys: String, CodingKey {
        case events, summary, month, year
        case datesWithEvents = "dates_with_events"
    }
}

struct TypeSummary: Codable {
    let total: Int
    let completed: Int
    let overdue: Int
}

struct ToggleEventResponse: Codable {
    let event: CalendarEvent
}

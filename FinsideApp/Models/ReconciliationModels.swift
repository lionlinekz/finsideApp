import Foundation

enum UncategorizedItemType: String, Codable {
    case payment
    case income

    var isIncome: Bool { self == .income }

    var title: String {
        switch self {
        case .payment: return "Расход"
        case .income: return "Доход"
        }
    }
}

struct UncategorizedTransaction: Codable, Identifiable, Hashable {
    let id: Int
    let type: String
    let date: String
    let amount: String
    let description: String
    let bank: String
    let uploadId: Int?
    let customerName: String

    enum CodingKeys: String, CodingKey {
        case id, type, date, amount, description, bank
        case uploadId = "upload_id"
        case customerName = "customer_name"
    }

    var itemType: UncategorizedItemType? {
        UncategorizedItemType(rawValue: type)
    }

    var amountValue: Double {
        Double(amount) ?? 0
    }
}

struct UncategorizedListResponse: Codable {
    let count: Int
    let results: [UncategorizedTransaction]
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case count, results
        case nextOffset = "next_offset"
    }
}

struct AssignCategoryResponse: Codable {
    let success: Bool
    let itemType: String
    let itemId: Int
    let uploadId: Int?
    let bank: String
    let categoryId: Int
    let subcategoryId: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case itemType = "item_type"
        case itemId = "item_id"
        case uploadId = "upload_id"
        case bank
        case categoryId = "category_id"
        case subcategoryId = "subcategory_id"
    }
}

struct SimilarMatchOption: Codable, Hashable {
    let countInUpload: Int
    let countAllBank: Int
    let directionLabel: String
    let description: String?
    let amount: String?

    enum CodingKeys: String, CodingKey {
        case description, amount
        case countInUpload = "count_in_upload"
        case countAllBank = "count_all_bank"
        case directionLabel = "direction_label"
    }
}

struct SubstringCandidate: Codable, Identifiable, Hashable {
    let text: String
    let countInUpload: Int
    let countAllBank: Int
    let isRecommended: Bool

    var id: String { text }

    enum CodingKeys: String, CodingKey {
        case text
        case countInUpload = "count_in_upload"
        case countAllBank = "count_all_bank"
        case isRecommended = "is_recommended"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        countInUpload = try c.decodeIfPresent(Int.self, forKey: .countInUpload) ?? 0
        countAllBank = try c.decodeIfPresent(Int.self, forKey: .countAllBank) ?? 0
        isRecommended = try c.decodeIfPresent(Bool.self, forKey: .isRecommended) ?? false
    }
}

struct SimilarCategorySuggestions: Codable {
    let exact: SimilarMatchOption?
    let substringCandidates: [SubstringCandidate]
    let direction: String
    let bank: String
    let uploadId: Int

    enum CodingKeys: String, CodingKey {
        case exact, direction, bank
        case substringCandidates = "substring_candidates"
        case uploadId = "upload_id"
    }
}

struct AutomationRuleItem: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String
    let bank: String
    let direction: String
    let match: String
    let matchDescription: String?
    let matchAmount: String?
    let matchSubstring: String?
    let categoryId: Int?
    let categoryName: String
    let subcategoryId: Int?
    let subcategoryName: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, bank, direction, match
        case matchDescription = "match_description"
        case matchAmount = "match_amount"
        case matchSubstring = "match_substring"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case subcategoryId = "subcategory_id"
        case subcategoryName = "subcategory_name"
        case createdAt = "created_at"
    }

    var kindTitle: String {
        kind == "exact" ? "Точное совпадение" : "Подстрока"
    }

    var directionTitle: String {
        direction == "income" ? "Доход" : "Расход"
    }
}

struct AutomationRulesResponse: Codable {
    let rules: [AutomationRuleItem]
}

struct BulkApplyCategoryResponse: Codable {
    let success: Bool
    let updated: Int
}

struct CreateTextAutocatRuleResponse: Codable {
    let success: Bool
    let updated: Int
    let bank: String
}

struct AutomationRuleMutationResponse: Codable {
    let success: Bool
    let rule: AutomationRuleItem?
}

struct CategorizationLaunch: Identifiable, Hashable {
    let id = UUID()
    let uploadId: Int?
    let iban: String?
}

import Foundation

enum CategoryType: String, Codable, CaseIterable, Identifiable {
    case expense = "EXPENSE"
    case income = "INCOME"
    case fin = "FIN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Расходные"
        case .income: return "Доходные"
        case .fin: return "Кредиты/депозиты"
        }
    }
}

struct SubcategoryItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let code: String
    let isTransfer: Bool
    let hasAutomation: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, code
        case isTransfer = "is_transfer"
        case hasAutomation = "has_automation"
    }
}

struct CategoryItem: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let code: String
    let type: String
    let subcategories: [SubcategoryItem]

    var categoryType: CategoryType? {
        CategoryType(rawValue: type)
    }
}

struct CategoryTypeOption: Codable, Hashable, Identifiable {
    let value: String
    let label: String

    var id: String { value }

    var asCategoryType: CategoryType? {
        CategoryType(rawValue: value)
    }
}

struct CategoriesResponse: Codable {
    let categories: [CategoryItem]
    let types: [CategoryTypeOption]
}

struct CategoryAddResponse: Codable {
    let ok: Bool
    let category: CategoryItem
}

struct SubcategoryAddResponse: Codable {
    let ok: Bool
    let subcategory: SubcategoryItem
    let categoryId: Int

    enum CodingKeys: String, CodingKey {
        case ok, subcategory
        case categoryId = "category_id"
    }
}

struct ExpenseAddPayment: Codable {
    let id: Int
    let amount: Double
    let date: String?
    let description: String
    let categoryId: Int?
    let subcategoryId: Int?
    let isPersonalMoney: Bool
    let paymentBank: String

    enum CodingKeys: String, CodingKey {
        case id, amount, date, description
        case categoryId = "category_id"
        case subcategoryId = "subcategory_id"
        case isPersonalMoney = "is_personal_money"
        case paymentBank = "payment_bank"
    }
}

struct ExpenseAddResponse: Codable {
    let ok: Bool
    let payment: ExpenseAddPayment
}

import Foundation

struct BankAccountItem: Codable, Identifiable, Hashable {
    let id: Int
    let bankId: Int
    let bankName: String
    let bankCode: String
    let iban: String
    let statementFrequency: String
    let statementFrequencyLabel: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, iban
        case bankId = "bank_id"
        case bankName = "bank_name"
        case bankCode = "bank_code"
        case statementFrequency = "statement_frequency"
        case statementFrequencyLabel = "statement_frequency_label"
        case createdAt = "created_at"
    }

    var displayTitle: String {
        if iban.isEmpty { return bankName }
        return "\(bankName) — \(iban)"
    }
}

struct BankRef: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let code: String
}

struct FrequencyOption: Codable, Hashable {
    let value: String
    let label: String
}

struct BankAccountsResponse: Codable {
    let accounts: [BankAccountItem]
}

struct BanksListResponse: Codable {
    let banks: [BankRef]
    let frequencies: [FrequencyOption]
}

struct BankAccountAddResponse: Codable {
    let ok: Bool
    let account: BankAccountItem
}

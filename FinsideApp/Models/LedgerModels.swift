import Foundation

struct LedgerLinesResponse: Codable {
    let count: Int
    let results: [LedgerLine]
    let nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case count, results
        case nextOffset = "next_offset"
    }
}

struct LedgerLine: Codable, Identifiable {
    let id: Int
    let date: String
    let amount: Double
    let description: String
    let paymentMethod: String
    let paymentBank: String

    enum CodingKeys: String, CodingKey {
        case id, date, amount, description
        case paymentMethod = "payment_method"
        case paymentBank = "payment_bank"
    }
}

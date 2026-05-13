import Foundation

/// Represents a monetary amount stored as minor units (tiyns/kopecks) to avoid floating-point errors.
struct MoneyAmount: Codable, Equatable, Hashable, Sendable {
    let minorUnits: Int64

    var majorUnits: Decimal {
        Decimal(minorUnits) / 100
    }

    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: majorUnits)) ?? "\(minorUnits / 100)"
    }

    var formattedWithCurrency: String {
        "\(formatted) ₸"
    }

    init(minorUnits: Int64) {
        self.minorUnits = minorUnits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            guard let decimal = Decimal(string: str) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Cannot parse money string: \(str)"
                )
            }
            self.minorUnits = NSDecimalNumber(decimal: decimal * 100).int64Value
        } else if let num = try? container.decode(Double.self) {
            self.minorUnits = Int64(num * 100)
        } else if let num = try? container.decode(Int64.self) {
            self.minorUnits = num
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode money amount"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(majorUnits)")
    }
}

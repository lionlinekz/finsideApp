import Foundation

struct BranchCompany: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let bin: String
    let companyType: String
    let companyTypeLabel: String
    let direction: String
    let taxMode: String
    let taxModeLabel: String
    /// Снимок эффективного режима (как в `effective_tax_for_company_dict` на бэкенде).
    let taxRegimeCode: String?
    let taxCalculationBase: String?
    let taxRate: Double?
    let taxRatePercent: Double?
    let pointCount: Int
    let points: [BranchPoint]

    enum CodingKeys: String, CodingKey {
        case id, name, bin, direction, points
        case companyType = "company_type"
        case companyTypeLabel = "company_type_label"
        case taxMode = "tax_mode"
        case taxModeLabel = "tax_mode_label"
        case taxRegimeCode = "tax_regime_code"
        case taxCalculationBase = "tax_calculation_base"
        case taxRate = "tax_rate"
        case taxRatePercent = "tax_rate_percent"
        case pointCount = "point_count"
    }
}

struct BranchPoint: Codable, Identifiable, Hashable {
    let id: Int
    let address: String
}

struct BranchesResponse: Codable {
    let companies: [BranchCompany]
}

struct CompanyAddResponse: Codable {
    let ok: Bool
    let company: BranchCompany
    let created: Bool
}

struct PointAddResponse: Codable {
    let ok: Bool
    let point: BranchPoint
}

struct PointEditResponse: Codable {
    let ok: Bool
    let point: BranchPoint
}

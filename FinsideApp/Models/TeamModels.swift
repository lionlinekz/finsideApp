import Foundation

struct TeamSnapshot: Codable {
    let companies: [TeamCompany]
    let roles: [TeamRole]
}

struct TeamCompany: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let pointCount: Int
    let points: [TeamPointRef]
    let positions: [TeamPositionRow]

    enum CodingKeys: String, CodingKey {
        case id, name, points, positions
        case pointCount = "point_count"
    }
}

struct TeamPointRef: Codable, Identifiable, Hashable {
    let id: Int
    let address: String
}

struct TeamPositionRow: Codable, Identifiable, Hashable {
    let id: Int
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let roleName: String
    let roleId: Int
    let pointIds: [Int]
    let pointsLabels: [String]

    enum CodingKeys: String, CodingKey {
        case id, email, phone
        case firstName = "first_name"
        case lastName = "last_name"
        case roleName = "role_name"
        case roleId = "role_id"
        case pointIds = "point_ids"
        case pointsLabels = "points_labels"
    }
}

struct TeamRole: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let needPoints: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case needPoints = "need_points"
    }
}

struct TeamAvailableProfilesResponse: Codable {
    let profiles: [AvailableProfileRow]
}

struct AvailableProfileRow: Codable, Identifiable {
    let id: Int
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
    }
}

struct TeamOkResponse: Codable {
    let ok: Bool
}

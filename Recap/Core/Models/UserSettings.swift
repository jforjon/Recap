import Foundation

struct UserSettings: Codable {
    var anthropicApiKey: String?

    enum CodingKeys: String, CodingKey {
        case anthropicApiKey = "anthropic_api_key"
    }

    static let empty = UserSettings(anthropicApiKey: nil)
}

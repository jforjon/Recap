import Foundation

struct UserSettings: Codable {
    var openaiApiKey: String?
    var anthropicApiKey: String?

    enum CodingKeys: String, CodingKey {
        case openaiApiKey = "openai_api_key"
        case anthropicApiKey = "anthropic_api_key"
    }

    static let empty = UserSettings(openaiApiKey: nil, anthropicApiKey: nil)
}

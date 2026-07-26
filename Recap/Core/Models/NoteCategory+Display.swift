import SwiftUI

extension NoteCategory {
    var displayText: String {
        switch self {
        case .talk: return "Talk"
        case .training: return "Training"
        case .panel: return "Panel"
        }
    }

    var dotColor: Color {
        switch self {
        case .talk: return AppColors.categoryTalk
        case .training: return AppColors.categoryTraining
        case .panel: return AppColors.categoryPanel
        }
    }
}

func formatShortDate(_ isoString: String) -> String {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = isoFormatter.date(from: isoString)
        ?? ISO8601DateFormatter().date(from: isoString)
        ?? Date()

    let displayFormatter = DateFormatter()
    displayFormatter.dateStyle = .medium
    return displayFormatter.string(from: date)
}

import SwiftUI

/// The app's single, consistent empty state: an illustrative SF Symbol in a
/// tinted circular badge, a title, a supporting line, and an optional action.
///
/// Use this everywhere a list/section has nothing to show so empties read the
/// same across Library, Projects, Notes and detail screens.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: Action? = nil

    struct Action {
        let title: String
        let systemImage: String?
        let handler: () -> Void

        init(title: String, systemImage: String? = nil, handler: @escaping () -> Void) {
            self.title = title
            self.systemImage = systemImage
            self.handler = handler
        }
    }

    var body: some View {
        VStack(spacing: Spacing.s4) {
            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(AppColors.accentGraphic)
            }

            VStack(spacing: Spacing.s2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .appTextStyle(.small)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }

            if let action {
                Button {
                    action.handler()
                } label: {
                    if let systemImage = action.systemImage {
                        Label(action.title, systemImage: systemImage)
                    } else {
                        Text(action.title)
                    }
                }
                .buttonStyle(.appSecondarySmall)
                .padding(.top, Spacing.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s8)
        .padding(.horizontal, Spacing.s6)
    }
}

import SwiftUI

/// Central place to tune spacing across the app — mirrors --space-* in tokens.css.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

/// Corner radii — mirrors --radius-* in tokens.css.
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
}

/// Colors — uses SwiftUI's adaptive system colors so light/dark mode work for
/// free. Swap these for your own palette (asset catalog color sets) whenever
/// you're ready to move off system defaults; nothing else in the app needs to change.
enum AppColor {
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let border = Color.primary.opacity(0.15)
    static let borderStrong = Color.primary.opacity(0.25)
}

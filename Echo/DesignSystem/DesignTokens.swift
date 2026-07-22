import SwiftUI

/// 1:1 port of the --space-* scale in tokens.css.
enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 28
    static let s8: CGFloat = 32
    static let s9: CGFloat = 36
    static let s10: CGFloat = 40

    // Aliases matching prior call sites (xs/sm/md/lg/xl) so nothing else needs touching.
    static let xs = s1
    static let sm = s2
    static let md = s3
    static let lg = s4
    static let xl = s6
}

/// 1:1 port of the --radius-* scale in tokens.css.
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let pill: CGFloat = 9999
}

/// Semantic colors used directly by design-system components — pulls from AppColors.
enum AppColor {
    static let cardBackground = AppColors.cardBackground
    static let border = AppColors.chipBorder
    static let borderStrong = AppColors.neutral900
}

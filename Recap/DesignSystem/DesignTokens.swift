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

/// Corner radii for the recap dark UI. Rounded, generous corners; controls are pills.
enum Radius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 16
    static let pill: CGFloat = 9999

    // Named component radii from the design.
    static let input: CGFloat = 14
    static let card: CGFloat = 16
    static let cardLarge: CGFloat = 18
    static let sheet: CGFloat = 20
}

extension View {
    /// Places a scrolling screen (List / Form / ScrollView) on the app's charcoal
    /// background instead of the default grouped system background.
    func recapBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppColors.background.ignoresSafeArea())
    }

    /// Clears a List row's default fill and separator so `AppCard`s float on the
    /// charcoal background with gaps, as in the design.
    func recapCardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

/// Semantic colors used directly by design-system components — pulls from AppColors.
enum AppColor {
    static let cardBackground = AppColors.surface
    static let border = AppColors.separator
    static let borderStrong = AppColors.separatorStrong
}

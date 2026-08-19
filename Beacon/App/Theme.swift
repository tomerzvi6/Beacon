import SwiftUI

enum Theme {
    enum Palette {
        static let deepTeal = Color("BeaconDeepTeal")
        static let softBlue = Color("BeaconSoftBlue")
        static let sage = Color("BeaconSage")
        static let sageDark = Color("BeaconSageDark")
        static let coralBackground = Color("BeaconCoralBg")
        static let coralAccent = Color("BeaconCoralAccent")
        static let background = Color("BeaconBackground")
        static let cardBackground = Color("BeaconCardBackground")
        static let textPrimary = Color("BeaconTextPrimary")
        static let textSecondary = Color("BeaconTextSecondary")
        static let deepTealDark = Color(red: 0.06, green: 0.18, blue: 0.24)
        static let deepTealMid = Color(red: 0.22, green: 0.45, blue: 0.55)
        static let deepTealLight = Color(red: 0.34, green: 0.56, blue: 0.62)
        static let googleBlue = Color(red: 0.26, green: 0.52, blue: 0.96)
    }

    enum Typography {
        static let screenTitle = Font.system(size: 26, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 19, weight: .semibold, design: .rounded)
        static let cardTitle = Font.system(size: 17, weight: .semibold)
        static let bodyLarge = Font.system(size: 16, weight: .regular)
        static let body = Font.system(size: 15, weight: .regular)
        static let bodyEmphasis = Font.system(size: 15, weight: .semibold)
        static let caption = Font.system(size: 13, weight: .regular)
        static let captionEmphasis = Font.system(size: 13, weight: .semibold)
        static let tag = Font.system(size: 12, weight: .semibold)
        static let timeLabel = Font.system(size: 18, weight: .bold, design: .rounded)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    enum Layout {
        static let edgeBarHorizontalInset = Spacing.m
        static let topStatusStripTopInset: CGFloat = 0
        static let topStatusStripBottomGap = Spacing.s
        static let statusStripIconSize = Spacing.xl + Spacing.xs
        static let statusStripHorizontalPadding = Spacing.s + Spacing.xs
        static let statusStripVerticalPadding = Spacing.s
        static let statusStripTextSpacing: CGFloat = 1
        static let bottomTabBarHorizontalInset = Spacing.m
        static let bottomTabBarBottomInset: CGFloat = 0
        static let bottomTabBarVerticalPadding = Spacing.s
        static let bottomTabBarHorizontalPadding = Spacing.s
        static let bottomTabIconHeight = Spacing.l
        static let bottomTabItemMinHeight = Spacing.xxl + Spacing.s
        static let bottomTabLabelMinScale: CGFloat = 0.58
        static let compactPillVerticalPadding = Spacing.s - Spacing.xxs
        static let chipVerticalPadding = Spacing.s + Spacing.xxs
        static let controlVerticalPadding = Spacing.s + Spacing.xs
        static let prominentControlVerticalPadding = Spacing.m - Spacing.xxs
        static let minimumTouchTarget = Spacing.xxl + Spacing.xs
        static let floatingActionButtonSize = Spacing.xxl + Spacing.m
        // Clears the floating bottom tab bar + home indicator. Used as the
        // trailing bottom padding on every tab's scrollable content so the
        // last card (or a floating action button) never renders behind it.
        static let scrollContentBottomClearance = Spacing.xxl * 3
        // Clears the floating top status strip + status bar/Dynamic Island.
        // Used as the leading top padding on every tab's scrollable content
        // so the first card never scrolls up behind it (BeaconEdgeTopBar is
        // an opaque overlay, not a safeAreaInset — see RootTabView).
        static let scrollContentTopClearance = Spacing.xxl * 2
    }

    enum CornerRadius {
        static let chip: CGFloat = 16
        static let card: CGFloat = 20
        static let button: CGFloat = 14   // rectangular CTA buttons (Apple/Google sign-in)
        static let buttonPill: CGFloat = 24
    }

    enum Shadow {
        static let cardColor = Color.black.opacity(0.06)
        static let cardRadius: CGFloat = 12
        static let cardOffsetY: CGFloat = 4
    }
}

extension View {
    func beaconCardShadow() -> some View {
        shadow(
            color: Theme.Shadow.cardColor,
            radius: Theme.Shadow.cardRadius,
            x: 0,
            y: Theme.Shadow.cardOffsetY
        )
    }

    func beaconScreenBackground() -> some View {
        background(Theme.Palette.background.ignoresSafeArea())
    }

    func beaconHorizontalText(minScale: CGFloat = 0.7) -> some View {
        lineLimit(1)
            .truncationMode(.tail)
            .allowsTightening(true)
            .minimumScaleFactor(minScale)
    }
}

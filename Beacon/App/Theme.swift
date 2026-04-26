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
    }

    enum Typography {
        static let screenTitle = Font.system(size: 30, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
        static let cardTitle = Font.system(size: 18, weight: .semibold)
        static let bodyLarge = Font.system(size: 17, weight: .regular)
        static let body = Font.system(size: 16, weight: .regular)
        static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
        static let caption = Font.system(size: 14, weight: .regular)
        static let captionEmphasis = Font.system(size: 14, weight: .semibold)
        static let tag = Font.system(size: 13, weight: .semibold)
        static let timeLabel = Font.system(size: 20, weight: .bold, design: .rounded)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }

    enum CornerRadius {
        static let chip: CGFloat = 16
        static let card: CGFloat = 20
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
}

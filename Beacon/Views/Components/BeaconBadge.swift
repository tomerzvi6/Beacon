import SwiftUI

struct BeaconBadge: View {
    enum Tone {
        case sage
        case softBlue
        case coral
        case neutral

        var background: Color {
            switch self {
            case .sage: return Theme.Palette.sage
            case .softBlue: return Theme.Palette.softBlue
            case .coral: return Theme.Palette.coralBackground
            case .neutral: return Theme.Palette.background
            }
        }

        var foreground: Color {
            switch self {
            case .sage: return Theme.Palette.sageDark
            case .softBlue: return Theme.Palette.deepTeal
            case .coral: return Theme.Palette.coralAccent
            case .neutral: return Theme.Palette.textSecondary
            }
        }
    }

    var text: String
    var tone: Tone = .sage
    var leadingDot: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if leadingDot {
                Circle()
                    .fill(tone.foreground)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(Theme.Typography.tag)
        }
        .foregroundStyle(tone.foreground)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(tone.background)
        .clipShape(Capsule())
    }
}

#Preview("Badges") {
    VStack(spacing: Theme.Spacing.s) {
        BeaconBadge(text: "רפואי", tone: .softBlue)
        BeaconBadge(text: "שגרה", tone: .sage)
        BeaconBadge(text: "מצב יציב", tone: .sage, leadingDot: true)
        BeaconBadge(text: "זקוקים למנוחה", tone: .coral, leadingDot: true)
        BeaconBadge(text: "3 נותרו", tone: .softBlue)
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

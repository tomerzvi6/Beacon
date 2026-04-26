import SwiftUI

struct BeaconPrimaryButton: View {
    enum Variant {
        case solid
        case danger
    }

    var title: String
    var systemImage: String?
    var variant: Variant = .solid
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, Theme.Spacing.l)
            .foregroundStyle(.white)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.buttonPill, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private var background: Color {
        switch variant {
        case .solid: return Theme.Palette.deepTeal
        case .danger: return Theme.Palette.coralAccent
        }
    }
}

struct BeaconSecondaryButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, Theme.Spacing.l)
            .foregroundStyle(Theme.Palette.textPrimary)
            .background(Theme.Palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.buttonPill, style: .continuous)
                    .strokeBorder(Theme.Palette.textSecondary.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.buttonPill, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview("Buttons") {
    VStack(spacing: Theme.Spacing.m) {
        BeaconPrimaryButton(title: "קח עכשיו", systemImage: "checkmark.circle.fill") { }
        BeaconPrimaryButton(title: "סמן כנלקח עכשיו", variant: .danger) { }
        BeaconSecondaryButton(title: "הוסף הערה") { }
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

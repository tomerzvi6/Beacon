import SwiftUI

struct BeaconCard<Content: View>: View {
    enum Style {
        case plain
        case tinted(Color)
    }

    var style: Style = .plain
    var cornerRadius: CGFloat = Theme.CornerRadius.card
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .beaconCardShadow()
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .plain:
            Theme.Palette.cardBackground
        case .tinted(let color):
            color
        }
    }
}

#Preview("BeaconCard") {
    VStack(spacing: Theme.Spacing.m) {
        BeaconCard {
            Text("כרטיס לבן רגיל")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        BeaconCard(style: .tinted(Theme.Palette.sage)) {
            Text("כרטיס עם רקע מרווה")
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

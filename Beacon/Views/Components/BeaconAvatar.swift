import SwiftUI

struct BeaconAvatar: View {
    var systemImage: String
    var diameter: CGFloat = 44
    var tint: Color = Theme.Palette.sage
    var foreground: Color = Theme.Palette.sageDark

    var body: some View {
        ZStack {
            Circle()
                .fill(tint)
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.5, weight: .medium))
                .foregroundStyle(foreground)
        }
        .frame(width: diameter, height: diameter)
    }
}

#Preview("Avatars") {
    HStack(spacing: Theme.Spacing.m) {
        BeaconAvatar(systemImage: "person.crop.circle.fill")
        BeaconAvatar(systemImage: "person.crop.circle", tint: Theme.Palette.softBlue, foreground: Theme.Palette.deepTeal)
        BeaconAvatar(systemImage: "bell.fill", diameter: 56, tint: Theme.Palette.coralBackground, foreground: Theme.Palette.coralAccent)
    }
    .padding()
    .beaconScreenBackground()
}

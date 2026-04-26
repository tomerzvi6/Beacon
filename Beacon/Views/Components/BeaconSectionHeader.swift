import SwiftUI

struct BeaconSectionHeader: View {
    var title: String
    var systemImage: String?
    var accessory: AnyView?

    init(title: String, systemImage: String? = nil, accessory: AnyView? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Palette.deepTeal)
            }
            Text(title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer(minLength: Theme.Spacing.s)
            accessory
        }
    }
}

#Preview("Section Header") {
    VStack(spacing: Theme.Spacing.m) {
        BeaconSectionHeader(title: "לוח זמנים משפחתי", systemImage: "calendar")
        BeaconSectionHeader(
            title: "תרופות להיום",
            accessory: AnyView(BeaconBadge(text: "3 נותרו", tone: .softBlue))
        )
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

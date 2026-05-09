import SwiftUI

struct BeaconScreenHeader: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#Preview("Screen Header") {
    VStack(spacing: Theme.Spacing.l) {
        BeaconScreenHeader(title: "מעקב טיפול פרואקטיבי", subtitle: "בוקר טוב. הנה מה שדרוש תשומת לב כרגע.")
        BeaconScreenHeader(title: "תיק רפואי", subtitle: "כל המסמכים והסיכומים שלכם, מסודרים וברורים.")
    }
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

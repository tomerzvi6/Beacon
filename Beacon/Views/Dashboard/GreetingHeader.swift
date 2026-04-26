import SwiftUI

struct GreetingHeader: View {
    var greeting: String
    var name: String
    var dateString: String

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text("\(greeting), \(name)")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("\(dateString) | סקירה יומית")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#Preview("GreetingHeader") {
    GreetingHeader(greeting: "בוקר טוב", name: "רונית", dateString: "יום שלישי, 12 באוקטובר")
        .padding()
        .beaconScreenBackground()
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}

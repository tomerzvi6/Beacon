import SwiftUI

struct DocumentFilterChips: View {
    @Binding var selection: MedicalDocumentKind
    var options: [MedicalDocumentKind] = [.all, .visitSummary, .bloodTest]

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(option.displayLabel)
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(option == selection ? .white : Theme.Palette.textPrimary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, Theme.Spacing.m)
                        .background(option == selection ? Theme.Palette.deepTeal : Theme.Palette.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Theme.Palette.textSecondary.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.xs) {
                Text("סינון")
                    .font(Theme.Typography.captionEmphasis)
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.vertical, 10)
            .padding(.horizontal, Theme.Spacing.m)
            .background(Theme.Palette.cardBackground)
            .clipShape(Capsule())
        }
    }
}

#Preview("DocumentFilterChips") {
    @Previewable @State var selection: MedicalDocumentKind = .all
    return DocumentFilterChips(selection: $selection)
        .padding()
        .beaconScreenBackground()
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}

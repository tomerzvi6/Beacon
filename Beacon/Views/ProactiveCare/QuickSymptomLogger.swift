import SwiftUI

struct QuickSymptomLogger: View {
    var onLog: (SymptomType) -> Void

    private let quickOptions: [SymptomType] = [.nausea, .fatigue, .pain]

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
            BeaconSectionHeader(title: "דיווח מהיר")

            HStack(spacing: Theme.Spacing.m) {
                ForEach(quickOptions) { symptom in
                    symptomButton(symptom)
                }
            }

            Button {
                onLog(.custom)
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16, weight: .semibold))
                    Text("הוסף מדד חדש")
                        .font(Theme.Typography.bodyEmphasis)
                        .beaconHorizontalText()
                }
                .foregroundStyle(Theme.Palette.sageDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Layout.prominentControlVerticalPadding)
                .background(Theme.Palette.sage)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func symptomButton(_ symptom: SymptomType) -> some View {
        Button {
            onLog(symptom)
        } label: {
            VStack(spacing: Theme.Spacing.s) {
                ZStack {
                    Circle()
                        .fill(tint(for: symptom).opacity(0.4))
                    Image(systemName: symptom.iconSymbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint(for: symptom))
                }
                .frame(width: 56, height: 56)
                Text(symptom.displayLabel)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .beaconHorizontalText(minScale: 0.62)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.m)
            .background(Theme.Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            .beaconCardShadow()
        }
        .buttonStyle(.plain)
    }

    private func tint(for symptom: SymptomType) -> Color {
        switch symptom {
        case .nausea: return Theme.Palette.sageDark
        case .fatigue: return Theme.Palette.deepTeal
        case .pain: return Theme.Palette.coralAccent
        case .custom: return Theme.Palette.sageDark
        }
    }
}

#Preview("QuickSymptomLogger") {
    QuickSymptomLogger(onLog: { _ in })
        .padding()
        .beaconScreenBackground()
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}

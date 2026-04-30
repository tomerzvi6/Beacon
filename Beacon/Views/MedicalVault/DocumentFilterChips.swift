import SwiftUI

/// Category filter row. Phase 9.3 swap: bound to an optional
/// `BackendDocumentCategory?` (nil = all). The view model passes the
/// chosen category straight into the GET /v1/documents/ query.
struct DocumentFilterChips: View {
    @Binding var selection: BackendDocumentCategory?
    /// Subset of categories surfaced as quick chips. Most users only
    /// need lab + visit summary + prescription day-to-day; the rest
    /// are reachable through the (TODO) full filter sheet.
    var options: [BackendDocumentCategory] = [.lab, .visitSummary, .prescription, .imaging]

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            chip(label: "הכל", isSelected: selection == nil) {
                selection = nil
            }
            ForEach(options) { option in
                chip(label: option.displayLabel, isSelected: selection == option) {
                    selection = (selection == option) ? nil : option
                }
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

    private func chip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.captionEmphasis)
                .foregroundStyle(isSelected ? .white : Theme.Palette.textPrimary)
                .padding(.vertical, 10)
                .padding(.horizontal, Theme.Spacing.m)
                .background(isSelected ? Theme.Palette.deepTeal : Theme.Palette.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Theme.Palette.textSecondary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("DocumentFilterChips") {
    @Previewable @State var selection: BackendDocumentCategory? = nil
    return DocumentFilterChips(selection: $selection)
        .padding()
        .beaconScreenBackground()
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}

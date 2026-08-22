import SwiftUI

/// Category filter row. Phase 9.3 swap: bound to an optional
/// `BackendDocumentCategory?` (nil = all). The view model passes the
/// chosen category straight into the GET /v1/documents/ query.
struct DocumentFilterChips: View {
    @Binding var selection: BackendDocumentCategory?
    /// Subset of categories surfaced as quick chips. Most users only
    /// need lab + visit summary + prescription day-to-day; the rest
    /// are reachable through the "עוד קטגוריות" chip below.
    var options: [BackendDocumentCategory] = [.lab, .visitSummary, .prescription, .imaging]
    @State private var showingMoreCategories = false

    private var moreOptions: [BackendDocumentCategory] {
        BackendDocumentCategory.allCases.filter { !options.contains($0) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                chip(label: "הכל", isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(options) { option in
                    chip(label: option.displayLabel, isSelected: selection == option) {
                        selection = (selection == option) ? nil : option
                    }
                }
                Button {
                    showingMoreCategories = true
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(selection.map { moreOptions.contains($0) ? $0.displayLabel : "עוד קטגוריות" } ?? "עוד קטגוריות")
                            .font(Theme.Typography.captionEmphasis)
                            .beaconHorizontalText(minScale: 0.6)
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selection.map(moreOptions.contains) == true ? .white : Theme.Palette.textSecondary)
                    .padding(.vertical, Theme.Layout.chipVerticalPadding)
                    .padding(.horizontal, Theme.Spacing.m)
                    .background(selection.map(moreOptions.contains) == true ? Theme.Palette.deepTeal : Theme.Palette.cardBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .confirmationDialog("עוד קטגוריות", isPresented: $showingMoreCategories, titleVisibility: .visible) {
            ForEach(moreOptions) { option in
                Button(option.displayLabel) { selection = (selection == option) ? nil : option }
            }
            Button("ביטול", role: .cancel) { }
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
                .beaconHorizontalText(minScale: 0.6)
                .padding(.vertical, Theme.Layout.chipVerticalPadding)
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

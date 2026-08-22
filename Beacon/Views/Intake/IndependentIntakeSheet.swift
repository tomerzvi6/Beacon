import SwiftUI

/// Independent-mode intake menu — the "אל תסדרו כלום, רק תצלמו" entry point.
/// Four capture paths, ordered by how often families need them.
struct IndependentIntakeSheet: View {
    let onBatchScan: () -> Void
    let onMedicationLabel: () -> Void
    let onAppointment: () -> Void
    let onFiles: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // A plain VStack here would let the sheet's `.medium` detent (or a
            // larger Dynamic Type size) clip the bottom row instead of
            // scrolling to it — ScrollView guarantees every row is reachable
            // regardless of detent or text size.
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    Text("אל תסדרו כלום — רק תצלמו. ביקון מזהה, מתייק ומסכם לבד.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    row(
                        icon: "square.stack.3d.up.fill",
                        title: "ערימת מסמכים",
                        subtitle: "צלמו דף אחרי דף — מכתבים, סיכומים, בדיקות",
                        tint: Theme.Palette.deepTeal,
                        action: { dismiss(); onBatchScan() }
                    )
                    row(
                        icon: "pills.fill",
                        title: "קופסת תרופה",
                        subtitle: "צלמו את מדבקת בית המרקחת — נזהה מינון ותדירות",
                        tint: Theme.Palette.sageDark,
                        action: { dismiss(); onMedicationLabel() }
                    )
                    row(
                        icon: "calendar.badge.plus",
                        title: "זימון תור",
                        subtitle: "צילום מסך של SMS או מכתב זימון — התור ייכנס ליומן",
                        tint: Theme.Palette.softBlue,
                        action: { dismiss(); onAppointment() }
                    )
                    row(
                        icon: "doc.fill",
                        title: "קובץ / PDF",
                        subtitle: "מסמך שכבר שמור במכשיר או ב-iCloud",
                        tint: Theme.Palette.coralAccent,
                        action: { dismiss(); onFiles() }
                    )
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle("הוספה לתיק")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func row(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.Layout.minimumTouchTarget, height: Theme.Layout.minimumTouchTarget)
                    .background(tint, in: Circle())
                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.left")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("IndependentIntakeSheet") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            IndependentIntakeSheet(
                onBatchScan: {},
                onMedicationLabel: {},
                onAppointment: {},
                onFiles: {}
            )
        }
        .environment(\.layoutDirection, .rightToLeft)
}
#endif

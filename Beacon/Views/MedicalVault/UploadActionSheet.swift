import SwiftUI

/// First sheet of the upload flow — three big touch targets covering the
/// three iOS file-acquisition paths. Each button dismisses the sheet and
/// fires a callback so the parent can present the matching system picker.
struct UploadActionSheet: View {
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.m) {
                row(
                    icon: "camera.fill",
                    title: "צילום",
                    subtitle: "צלמו מסמך מודפס או טופס",
                    tint: Theme.Palette.deepTeal,
                    action: { dismiss(); onCamera() }
                )
                row(
                    icon: "photo.on.rectangle.angled",
                    title: "בחירת תמונה",
                    subtitle: "בחרו תמונה מהאלבום",
                    tint: Theme.Palette.sage,
                    action: { dismiss(); onPhotos() }
                )
                row(
                    icon: "doc.fill",
                    title: "בחירת קובץ",
                    subtitle: "PDF או תמונה ממכשיר / iCloud",
                    tint: Theme.Palette.softBlue,
                    action: { dismiss(); onFiles() }
                )
                Spacer()
            }
            .padding(Theme.Spacing.l)
            .navigationTitle("הוספת מסמך")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium])
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
                    .frame(width: 44, height: 44)
                    .background(tint, in: Circle())
                VStack(alignment: .trailing, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
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
#Preview("UploadActionSheet") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            UploadActionSheet(onCamera: {}, onPhotos: {}, onFiles: {})
        }
        .environment(\.layoutDirection, .rightToLeft)
}
#endif

import SwiftUI

/// Second sheet of the upload flow — once a file has been picked, the
/// user can optionally tag it with a category and (if patient/co_owner)
/// mark it private. Hitting "העלה" forwards the choices to the parent.
struct UploadMetadataSheet: View {
    let filename: String
    let sourceLabel: String
    let mimeType: String
    let byteCount: Int
    let userRole: String?
    let onUpload: (BackendDocumentCategory?, Bool) -> Void
    let onCancel: () -> Void

    @State private var selectedCategory: BackendDocumentCategory? = nil
    @State private var isPrivate: Bool = false

    private var canMarkPrivate: Bool {
        userRole == "patient" || userRole == "co_owner"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("מסמך") {
                    LabeledContent("שם הקובץ") {
                        Text(filename)
                            .font(.caption)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("מקור", value: sourceLabel)
                    LabeledContent("סוג", value: humanMimeLabel)
                    LabeledContent("גודל", value: ByteCountFormatter.string(
                        fromByteCount: Int64(byteCount), countStyle: .file
                    ))
                }

                Section {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: Theme.Spacing.s) {
                        ForEach(BackendDocumentCategory.allCases) { category in
                            CategoryChip(
                                category: category,
                                isSelected: selectedCategory == category
                            ) {
                                if selectedCategory == category {
                                    selectedCategory = nil
                                } else {
                                    selectedCategory = category
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("קטגוריה (לא חובה)")
                } footer: {
                    Text("ללא בחירה — ביקון יקטלג את המסמך אוטומטית בעת ההעלאה.")
                }

                if canMarkPrivate {
                    Section {
                        Toggle("מסמך פרטי", isOn: $isPrivate)
                    } footer: {
                        Text("מטפלים שאינם מעלי המסמך לא יראו אותו.")
                    }
                }
            }
            .navigationTitle("פרטי המסמך")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("העלה") {
                        onUpload(selectedCategory, isPrivate)
                    }
                    .bold()
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var humanMimeLabel: String {
        switch mimeType {
        case "application/pdf": return "PDF"
        case "image/jpeg":      return "תמונה (JPEG)"
        case "image/png":       return "תמונה (PNG)"
        case "image/heic", "image/heif": return "תמונה (HEIC)"
        default:                return mimeType
        }
    }
}

private struct CategoryChip: View {
    let category: BackendDocumentCategory
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: category.iconSymbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(category.displayLabel)
                    .font(Theme.Typography.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? Theme.Palette.deepTeal.opacity(0.15)
                    : Theme.Palette.cardBackground
            )
            .foregroundStyle(
                isSelected ? Theme.Palette.deepTeal : Theme.Palette.textPrimary
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Theme.Palette.deepTeal
                            : Theme.Palette.textSecondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

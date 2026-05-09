import SwiftUI

/// Full-page view for a parsed document. Phase 9.3 swap: consumes
/// `BackendDocument` directly and surfaces:
///  - The full Hebrew summary (`parsed_summary_he`)
///  - The flagged-for-review banner if `flagged_for_review == true`
///  - Metadata: category, upload date, privacy, status
///
/// Suggested-task auto-creation moved to Phase 4 — backend already
/// persists suggested Tasks during parsing; the iOS surface for
/// approving them lives in the dashboard.
struct DocumentDetailView: View {
    var document: BackendDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                header
                if document.flagged_for_review {
                    flaggedBanner
                }
                summaryBlock
                metadataBlock
            }
            .padding(Theme.Spacing.m)
        }
        .beaconScreenBackground()
        .navigationTitle(document.filename ?? "מסמך")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text(document.filename ?? "מסמך")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
            HStack(spacing: Theme.Spacing.s) {
                if let category = document.typedCategory {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: category.iconSymbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(category.displayLabel)
                            .font(Theme.Typography.tag)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Layout.chipVerticalPadding)
                    .background(Theme.Palette.sage.opacity(0.4))
                    .clipShape(Capsule())
                }
                if document.is_private {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("פרטי")
                            .font(Theme.Typography.tag)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .padding(.horizontal, Theme.Layout.chipVerticalPadding)
                    .background(Theme.Palette.softBlue.opacity(0.5))
                    .clipShape(Capsule())
                }
            }
            .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Flagged-for-review banner

    private var flaggedBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Palette.coralAccent)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text("המסמך מכיל פרטים שלא תואמים את החולה הרשום")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("בדקו את המסמך לפני שמירה. ייתכן ששויך לחולה אחר בטעות.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let reason = document.flag_reason, !reason.isEmpty {
                    Text("(\(reason))")
                        .font(Theme.Typography.caption.monospaced())
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Palette.coralBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous)
                .strokeBorder(Theme.Palette.coralAccent.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Summary block

    @ViewBuilder
    private var summaryBlock: some View {
        if document.isFailed {
            BeaconCard {
                VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.coralAccent)
                        Text("פרסור נכשל")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("חזור למסך הראשי ונסה שוב להעלות או לפרסר את המסמך.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } else if document.isParsing {
            BeaconCard {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView().controlSize(.regular).tint(Theme.Palette.deepTeal)
                    Text("מעבדים את המסמך…")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                }
                .padding(Theme.Spacing.s)
            }
        } else if let full = document.parsed_summary_he, !full.isEmpty {
            BeaconCard {
                VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        BeaconBadge(text: "AI", tone: .softBlue, leadingDot: true)
                        Text("סיכום מלא")
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    Text(full)
                        .font(Theme.Typography.bodyLarge)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } else {
            BeaconCard {
                Text("אין סיכום AI למסמך זה.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Metadata block

    private var metadataBlock: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                metadataRow(label: "סוג קובץ", value: document.mime_type)
                metadataRow(label: "סטטוס", value: statusLabel)
                metadataRow(label: "הועלה", value: Self.dateString(document.created_at))
                if let parsedAt = document.parsed_at {
                    metadataRow(label: "פרסור הסתיים", value: Self.dateString(parsedAt))
                }
                if document.category_source == "user", let suggested = document.category_suggested {
                    metadataRow(
                        label: "המודל הציע קטגוריה",
                        value: BackendDocumentCategory(rawValue: suggested)?.displayLabel ?? suggested
                    )
                }
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(value)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
            Spacer()
            Text(label)
                .font(Theme.Typography.captionEmphasis)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var statusLabel: String {
        switch document.status {
        case "uploaded":  return "הועלה"
        case "finalized": return "ממתין לפרסור"
        case "parsing":   return "מעבדים…"
        case "parsed":    return "פורסר"
        case "failed":    return "נכשל"
        default:          return document.status
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

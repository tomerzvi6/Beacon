import SwiftUI

/// Single document row in the Medical Vault. Phase 9.3 swap: consumes
/// `BackendDocument` directly and renders one of three body states —
/// parsing-in-progress, failure-with-retry, or the parsed simple
/// summary. The flagged-for-review banner intentionally lives only in
/// the detail view.
struct DocumentCard: View {
    var document: BackendDocument
    var isPolling: Bool
    var onOpen: () -> Void
    var onRetryParse: () -> Void

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                headerRow
                bodyContent
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            BeaconAvatar(
                systemImage: document.typedCategory?.iconSymbol ?? "doc",
                diameter: 40,
                tint: Theme.Palette.sage,
                foreground: Theme.Palette.sageDark
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(document.filename ?? "מסמך ללא שם")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(dateString)
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if document.is_private {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("פרטי")
                            .font(Theme.Typography.tag)
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }

    private var subtitle: String {
        document.typedCategory?.displayLabel ?? document.category ?? "ללא קטגוריה"
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: document.created_at)
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyContent: some View {
        if document.isFailed {
            failureRow
        } else if document.isParsing || isPolling {
            parsingRow
        } else if let summary = document.parsed_summary_simple_he, !summary.isEmpty {
            parsedSummaryRow(summary)
        } else {
            // Parsed but the model produced no simple summary — degrade
            // gracefully rather than showing nothing.
            openRow
        }
    }

    private var parsingRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.Palette.deepTeal)
            Text("מעבדים את המסמך…")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var failureRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.coralAccent)
            VStack(alignment: .trailing, spacing: 2) {
                Text("פרסור נכשל — נסה שוב")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Spacer()
            Button(action: onRetryParse) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Palette.deepTeal)
            }
            .accessibilityLabel("נסה שוב לפרסר את המסמך")
        }
        .padding(.vertical, 4)
    }

    private func parsedSummaryRow(_ summary: String) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            Text(summary)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(4)
            Divider()
            HStack {
                Button(action: onOpen) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("צפה בסיכום המלא")
                            .font(Theme.Typography.captionEmphasis)
                    }
                    .foregroundStyle(Theme.Palette.deepTeal)
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: Theme.Spacing.xs) {
                    Text("סוכם ע״י AI")
                        .font(Theme.Typography.tag)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.Palette.sageDark)
            }
        }
    }

    private var openRow: some View {
        Button(action: onOpen) {
            HStack {
                Image(systemName: "arrow.down.circle")
                Text("צפה במסמך")
                    .font(Theme.Typography.bodyEmphasis)
                Spacer()
            }
            .foregroundStyle(Theme.Palette.deepTeal)
            .padding(.vertical, 12)
            .padding(.horizontal, Theme.Spacing.m)
            .background(Theme.Palette.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

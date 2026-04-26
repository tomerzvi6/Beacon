import SwiftUI

struct DocumentDetailView: View {
    enum PreviewMode: String, CaseIterable, Identifiable {
        case aiSummary
        case original

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .aiSummary: return "סיכום AI מופשט"
            case .original: return "מסמך מקורי"
            }
        }
    }

    var document: MedicalDocument
    var summary: AISummary?
    var onAddSuggestedTasks: ([String]) -> Void

    @State private var mode: PreviewMode = .aiSummary
    @State private var importedCount: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                header
                Picker("תצוגה", selection: $mode) {
                    ForEach(PreviewMode.allCases) { option in
                        Text(option.displayLabel).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .aiSummary {
                    aiSummaryContent
                } else {
                    originalContent
                }
            }
            .padding(Theme.Spacing.m)
        }
        .beaconScreenBackground()
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text(document.title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
            Text(document.sourceDescription)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var aiSummaryContent: some View {
        if let summary {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                BeaconCard {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                        HStack(spacing: Theme.Spacing.s) {
                            BeaconBadge(text: "AI", tone: .softBlue, leadingDot: true)
                            Text(summary.headline)
                                .font(Theme.Typography.cardTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        Text(summary.summaryText)
                            .font(Theme.Typography.bodyLarge)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Divider()

                        Text("נקודות עיקריות")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        ForEach(summary.keyPoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                                Text(point)
                                    .font(Theme.Typography.body)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text("•")
                                    .foregroundStyle(Theme.Palette.sageDark)
                            }
                        }

                        if let recommendation = summary.recommendation {
                            Divider()
                            Text("המלצה: \(recommendation)")
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.sageDark)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }

                if !summary.suggestedTasks.isEmpty {
                    BeaconCard(style: .tinted(Theme.Palette.sage)) {
                        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                            Text("משימות מוצעות להוסיף ליומן")
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.sageDark)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            ForEach(summary.suggestedTasks) { suggestion in
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("• \(suggestion.title)")
                                        .font(Theme.Typography.body)
                                        .foregroundStyle(Theme.Palette.textPrimary)
                                    if let detail = suggestion.detail {
                                        Text(detail)
                                            .font(Theme.Typography.caption)
                                            .foregroundStyle(Theme.Palette.textSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            BeaconPrimaryButton(
                                title: importedCount != nil
                                    ? "נוספו \(importedCount!) משימות ליומן ✓"
                                    : "הוסף משימות מוצעות ליומן",
                                systemImage: "calendar.badge.plus",
                                isEnabled: importedCount == nil
                            ) {
                                onAddSuggestedTasks(summary.suggestedTasks.map(\.title))
                                importedCount = summary.suggestedTasks.count
                            }
                        }
                    }
                }
            }
        } else {
            Text("אין סיכום AI למסמך זה.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    private var originalContent: some View {
        BeaconCard {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: document.fileType == .image ? "photo.fill.on.rectangle.fill" : "doc.richtext.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Theme.Palette.softBlue)
                    .padding(Theme.Spacing.xl)
                Text("זוהי תצוגה מדומה של המסמך המקורי.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                if let size = document.fileSizeLabel {
                    Text("\(document.fileType.displayLabel) · \(size)")
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                BeaconSecondaryButton(title: "הורד / שתף", systemImage: "square.and.arrow.down") { }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview("DocumentDetailView") {
    NavigationStack {
        DocumentDetailView(
            document: MedicalDocument(
                title: "סיכום ביקור אונקולוג",
                sourceDescription: "ד״ר לוי, בי״ח שיבא",
                documentDate: Date(),
                kind: .visitSummary,
                fileType: .pdf,
                fileSizeLabel: "1.1 MB",
                hasAISummary: true,
                aiSummaryKey: SampleAISummaries.oncologyVisit.id
            ),
            summary: SampleAISummaries.oncologyVisit,
            onAddSuggestedTasks: { _ in }
        )
    }
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

import SwiftUI
import SwiftData

struct DocumentCard: View {
    var document: MedicalDocument
    var summary: AISummary?
    var onOpen: () -> Void

    @State private var showingAISummary = true

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: document.documentDate)
    }

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                headerRow
                if document.hasAISummary, summary != nil {
                    viewTabs
                }
                bodyContent
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            BeaconAvatar(
                systemImage: document.kind.iconSymbol,
                diameter: 40,
                tint: Theme.Palette.sage,
                foreground: Theme.Palette.sageDark
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(document.title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                Text(document.sourceDescription)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(dateString)
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let size = document.fileSizeLabel {
                    HStack(spacing: 4) {
                        Text(document.fileType.displayLabel)
                            .font(Theme.Typography.tag)
                        Text(size)
                            .font(Theme.Typography.tag)
                    }
                    .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var viewTabs: some View {
        HStack(spacing: Theme.Spacing.s) {
            tabButton(title: "סיכום AI מופשט", isSelected: showingAISummary) {
                showingAISummary = true
            }
            tabButton(title: "מסמך מקורי", isSelected: !showingAISummary) {
                showingAISummary = false
            }
        }
    }

    private func tabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.captionEmphasis)
                .foregroundStyle(isSelected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, Theme.Spacing.m)
                .background(isSelected ? Theme.Palette.sage : Theme.Palette.background)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let summary, showingAISummary {
            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                Text("נקודות עיקריות:")
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
                    Text("המלצה: \(recommendation)")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Divider()
                HStack {
                    Button(action: onOpen) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("צפה במסמך המלא")
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
        } else if !showingAISummary {
            Button(action: onOpen) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: document.fileType == .image ? "photo.fill" : "doc.richtext.fill")
                    Text("צפה במסמך המלא")
                        .font(Theme.Typography.bodyEmphasis)
                }
                .foregroundStyle(Theme.Palette.deepTeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.Palette.softBlue.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
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
}

#Preview("DocumentCard") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    let docs = try! container.mainContext.fetch(FetchDescriptor<MedicalDocument>())
    return ScrollView {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(docs) { doc in
                DocumentCard(
                    document: doc,
                    summary: doc.aiSummaryKey.flatMap { SampleAISummaries.summary(for: $0) },
                    onOpen: { }
                )
            }
        }
        .padding()
    }
    .beaconScreenBackground()
    .modelContainer(container)
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

import SwiftUI

/// Hero card pinned to the top of the Medical Vault. For the demo flow
/// this intentionally uses the original static mock AI summary.
struct AISmartSummaryFeatureCard: View {
    var summary: AISummary
    var onReadFullSummary: () -> Void
    var onAddSuggestedTasks: () -> Void
    var importedTaskCount: Int?
    /// True when this card is showing the static demo summary, not a real
    /// parsed document — without a visible label a first-time user has no
    /// way to tell this isn't their relative's actual medical data.
    var isExample: Bool = false

    private let gradient = LinearGradient(
        colors: [
            Theme.Palette.deepTeal,
            Theme.Palette.deepTealMid,
            Theme.Palette.deepTealLight
        ],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
            HStack {
                BeaconAvatar(
                    systemImage: "leaf.fill",
                    diameter: 42,
                    tint: .white.opacity(0.2),
                    foreground: .white
                )
                Spacer()
            }

            HStack(spacing: Theme.Spacing.s) {
                BeaconBadge(text: isExample ? "דוגמה להמחשה" : "חדש", tone: isExample ? .coral : .softBlue)
                Text("סיכום AI חכם")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if isExample {
                Text("כך תיראה תמצית לאחר שתעלו מסמך:")
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text(summary.summaryText)
                .font(Theme.Typography.body)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("סיכום אוטומטי — אינו ייעוץ רפואי. בכל שאלה פנו לצוות המטפל.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .trailing)

            Button(action: onReadFullSummary) {
                HStack {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 14, weight: .semibold))
                    Text("קרא סיכום מלא")
                        .font(Theme.Typography.bodyEmphasis)
                        .beaconHorizontalText()
                    Spacer()
                }
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.vertical, Theme.Layout.prominentControlVerticalPadding)
                .padding(.horizontal, Theme.Spacing.m)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack {
                Spacer()
                if let importedTaskCount, importedTaskCount > 0 {
                    Label("נוספו \(importedTaskCount) משימות ליומן", systemImage: "checkmark.circle.fill")
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(.white)
                } else {
                    Button(action: onAddSuggestedTasks) {
                        Label("הוסף משימות מוצעות", systemImage: "calendar.badge.plus")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.vertical, Theme.Spacing.s)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
        .beaconCardShadow()
    }
}

struct AISummaryDetailView: View {
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

    var summary: AISummary
    var onAddSuggestedTasks: ([String]) -> Void
    var isExample: Bool = false

    @State private var mode: PreviewMode = .aiSummary
    @State private var importedCount: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                if isExample {
                    Text("דוגמה להמחשה — לא מידע רפואי אמיתי. כך תיראה תמצית לאחר שתעלו מסמך.")
                        .font(Theme.Typography.captionEmphasis)
                        .foregroundStyle(Theme.Palette.coralAccent)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(Theme.Spacing.s)
                        .background(Theme.Palette.coralBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
                }
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
        .navigationTitle(summary.headline)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text(summary.headline)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var aiSummaryContent: some View {
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
                            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
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
                                ? "נוספו \(importedCount ?? 0) משימות ליומן ✓"
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
    }

    private var originalContent: some View {
        BeaconCard {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(Theme.Palette.softBlue)
                    .padding(Theme.Spacing.xl)
                Text("זוהי תצוגה מדומה של המסמך המקורי.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                Text("PDF · 1.1 MB")
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textSecondary)
                BeaconSecondaryButton(title: "הורד / שתף", systemImage: "square.and.arrow.down") { }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct AISuggestedTask: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?
}

struct AISummary: Identifiable, Hashable {
    let id: String
    let headline: String
    let summaryText: String
    let keyPoints: [String]
    let recommendation: String?
    let suggestedTasks: [AISuggestedTask]
}

enum SampleAISummaries {
    static let oncologyVisit = AISummary(
        id: "oncology-visit-20231012",
        headline: "סיכום ביקור אונקולוג — 12.10.2023",
        summaryText: "הרופא דיווח על שיפור מתון במדדי הדם לעומת הביקור הקודם. הטיפול הנוכחי (תרופה X) ממשיך להיות יעיל, ולא נדרש שינוי במינון כרגע.",
        keyPoints: [
            "המטופלת מדווחת על הטבה כללית בתחושה.",
            "בדיקות הדם עדיין מראות מעט ירידה בברזל.",
            "המלצה: להמשיך בטיפול הנוכחי. לחזור לביקורת בעוד 3 חודשים עם בדיקות דם חוזרות."
        ],
        recommendation: "להמשיך בטיפול הנוכחי ולהקפיד על מנוחה.",
        suggestedTasks: [
            .init(id: "sug-onco-1", title: "לקבוע בדיקות דם חוזרות", detail: "יש לבצע כ-10 ימים לפני תור הביקורת הבא."),
            .init(id: "sug-onco-2", title: "לתאם תור ביקורת אונקולוגית", detail: "למועד של עוד כ-3 חודשים.")
        ]
    )

    static let bloodTest = AISummary(
        id: "blood-test-20231010",
        headline: "תוצאות בדיקת דם מקיפה",
        summaryText: "רוב הערכים נמצאים בטווח התקין. קיימת ירידה קלה בברזל ובוויטמין D, המלווה בתחושת עייפות מדווחת.",
        keyPoints: [
            "המוגלובין: 11.8 — מעט מתחת לטווח התקין.",
            "ויטמין D: נמוך מהרצוי.",
            "תפקוד כבד וכליות: תקין."
        ],
        recommendation: "לשקול תוסף ברזל וויטמין D בהמלצת הרופא המטפל.",
        suggestedTasks: [
            .init(id: "sug-blood-1", title: "לקנות תוספי ברזל וויטמין D", detail: "לאחר אישור מהרופא המטפל.")
        ]
    )

    static let prescriptionImage = AISummary(
        id: "prescription-20231005",
        headline: "צילום מרשם תרופות — אוקטובר",
        summaryText: "המרשם כולל תרופה למניעת בחילות ותרופה משככת כאבים. יש להקפיד על מועדי הנטילה.",
        keyPoints: [
            "זופרן — לפני הטיפול ולפי הצורך.",
            "פרצטמול — לפי הצורך, לא יותר מ-4 פעמים ביממה."
        ],
        recommendation: nil,
        suggestedTasks: [
            .init(id: "sug-rx-1", title: "לחדש מרשם בסופר-פארם", detail: "המרשם הנוכחי תקף עוד שבועיים.")
        ]
    )

    static let dashboardFeatured = oncologyVisit

    static func summary(for key: String) -> AISummary? {
        switch key {
        case oncologyVisit.id: return oncologyVisit
        case bloodTest.id: return bloodTest
        case prescriptionImage.id: return prescriptionImage
        default: return nil
        }
    }
}

#Preview("AISmartSummaryFeatureCard") {
    AISmartSummaryFeatureCard(
        summary: SampleAISummaries.oncologyVisit,
        onReadFullSummary: { },
        onAddSuggestedTasks: { },
        importedTaskCount: nil
    )
    .padding()
    .beaconScreenBackground()
    .environment(\.locale, Locale(identifier: "he_IL"))
    .environment(\.layoutDirection, .rightToLeft)
}

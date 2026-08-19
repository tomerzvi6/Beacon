import SwiftUI

/// Family-side detail view for a single caregiver check-in: Hebrew summary,
/// original note + language, structured fields, and follow-up actions.
struct CaregiverCheckInDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let checkIn: CaregiverCheckIn
    let viewModel: CaregiverLayerViewModel

    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    summaryCard
                    if !checkIn.alertReasons.isEmpty {
                        alertsCard
                    }
                    structuredFieldsCard
                    if let original = checkIn.freeTextOriginal, !original.isEmpty {
                        originalNoteCard(original)
                    }
                    actionsSection
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .beaconScreenBackground()
            .navigationTitle("דיווח מהמטפל/ת")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xs)
                        .padding(.horizontal, Theme.Spacing.l)
                        .background(.regularMaterial, in: Capsule())
                        .beaconCardShadow()
                        .padding(.bottom, Theme.Spacing.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toastMessage)
            .task(id: toastMessage) {
                guard toastMessage != nil else { return }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                toastMessage = nil
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Cards

    private var summaryCard: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                HStack {
                    Text("תקציר בעברית")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    BeaconBadge(
                        text: checkIn.attentionLevel.hebrewLabel,
                        tone: checkIn.needsAttention ? .coral : .sage,
                        leadingDot: true
                    )
                }
                Text(checkIn.translatedSummaryHebrew)
                    .font(Theme.Typography.bodyLarge)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("\(viewModel.caregiverName(for: checkIn)) · \(fullTimeString)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }

    private var alertsCard: some View {
        BeaconCard(style: .tinted(Theme.Palette.coralBackground)) {
            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralAccent)
                    Text("דורש תשומת לב")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                }
                ForEach(checkIn.alertReasons, id: \.self) { reason in
                    HStack(spacing: Theme.Spacing.s) {
                        Circle()
                            .fill(Theme.Palette.coralAccent)
                            .frame(width: 6, height: 6)
                        Text(reason)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var structuredFieldsCard: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                Text("פרטי הדיווח")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)

                fieldRow(icon: checkIn.mealStatus.iconSymbol, title: "אוכל", value: checkIn.mealStatus.hebrewLabel)
                fieldRow(icon: checkIn.hydrationStatus.iconSymbol, title: "שתייה", value: checkIn.hydrationStatus.hebrewLabel)
                fieldRow(icon: checkIn.sleepStatus.iconSymbol, title: "שינה", value: checkIn.sleepStatus.hebrewLabel)
                fieldRow(icon: "bolt.heart.fill", title: "כאב", value: "\(checkIn.painLevel)/10", highlight: checkIn.painLevel >= 7)
                fieldRow(icon: "face.dashed", title: "בחילה", value: "\(checkIn.nauseaLevel)/10", highlight: checkIn.nauseaLevel >= 7)
                fieldRow(icon: "moon.fill", title: "חולשה", value: "\(checkIn.fatigueLevel)/10", highlight: checkIn.fatigueLevel >= 7)
                fieldRow(
                    icon: checkIn.medicationStatus.iconSymbol,
                    title: "תרופות",
                    value: checkIn.medicationStatus.hebrewLabel,
                    highlight: checkIn.medicationStatus == .missed
                )
            }
        }
    }

    private func originalNoteCard(_ original: String) -> some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                HStack {
                    Text("ההודעה המקורית")
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    BeaconBadge(text: checkIn.originalLanguage.hebrewName, tone: .softBlue)
                }
                Text(original)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, checkIn.originalLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: Theme.Spacing.s) {
            if environment.canWrite(.tasks) {
                BeaconPrimaryButton(title: "צור משימה", systemImage: "checkmark.circle.fill") {
                    Task {
                        let created = await viewModel.createFollowUpTask(for: checkIn)
                        toastMessage = created ? "נוצרה משימה למעקב ✓" : "כבר קיימת משימה פתוחה לדיווח הזה"
                    }
                }
            }
            if !checkIn.isAcknowledged {
                BeaconSecondaryButton(title: "סמן כטופל", systemImage: "checkmark.seal") {
                    Task {
                        await viewModel.acknowledge(checkIn)
                        toastMessage = "הדיווח סומן כטופל ✓"
                    }
                }
            }
            if environment.canWrite(.feed) {
                BeaconSecondaryButton(title: "שתף במעגל התמיכה", systemImage: "bubble.left.and.bubble.right") {
                    Task {
                        await viewModel.shareToFeed(checkIn, authorMemberId: environment.currentUser.id)
                        toastMessage = "שותף במעגל התמיכה ✓"
                    }
                }
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private func fieldRow(icon: String, title: String, value: String, highlight: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(highlight ? Theme.Palette.coralAccent : Theme.Palette.deepTeal)
                .frame(width: Theme.Spacing.l)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(highlight ? Theme.Palette.coralAccent : Theme.Palette.textPrimary)
        }
    }

    private var fullTimeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "EEEE, d בMMMM · HH:mm"
        return formatter.string(from: checkIn.createdAt)
    }
}

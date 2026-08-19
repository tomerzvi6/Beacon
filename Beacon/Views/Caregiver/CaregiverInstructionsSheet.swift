import SwiftUI

/// Family-side management of standing instructions for the home caregiver.
/// The family composes in Hebrew from structured templates; the caregiver
/// sees them localized on the report screen.
struct CaregiverInstructionsSheet: View {
    let viewModel: CaregiverLayerViewModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var composingKind: CaregiverInstructionKind? = nil
    @State private var composerDetail = ""

    private var caregiverName: String {
        viewModel.activeCaregiver?.displayName ?? "המטפל/ת"
    }

    private var caregiverLanguage: CaregiverLanguage {
        viewModel.activeCaregiver?.preferredLanguage ?? .english
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    BeaconCard(style: .tinted(Theme.Palette.softBlue.opacity(0.35))) {
                        Text("ההוראות מוצגות ל\(caregiverName) בשפה שלו/ה (\(caregiverLanguage.hebrewName)) בכל פתיחה של מסך הדיווח.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if composingKind == nil {
                        templatePicker
                    } else {
                        composer
                    }

                    if !viewModel.activeInstructions.isEmpty {
                        BeaconSectionHeader(title: "הוראות פעילות")
                        ForEach(viewModel.activeInstructions) { instruction in
                            instructionRow(instruction)
                        }
                    } else if composingKind == nil {
                        BeaconCard {
                            BeaconEmptyState(
                                systemImage: "list.bullet.clipboard",
                                title: "אין הוראות פעילות",
                                message: "בחרו תבנית למעלה — למשל תרופה ושעה — וההוראה תופיע אצל \(caregiverName) בשפה שלו/ה."
                            )
                        }
                    }
                }
                .padding(Theme.Spacing.m)
            }
            .beaconScreenBackground()
            .navigationTitle("הוראות למטפל/ת")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Template picker

    private var templatePicker: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            BeaconSectionHeader(title: "הוראה חדשה")
            ForEach(CaregiverInstructionKind.allCases) { kind in
                Button {
                    composingKind = kind
                    composerDetail = ""
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: kind.iconSymbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Palette.deepTeal)
                            .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                            .background(Theme.Palette.softBlue.opacity(0.35), in: Circle())
                        Text(kind.hebrewLabel)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .padding(Theme.Spacing.m)
                    .background(Theme.Palette.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                if let kind = composingKind {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: kind.iconSymbol)
                            .foregroundStyle(Theme.Palette.deepTeal)
                        Text(kind.hebrewLabel)
                            .font(Theme.Typography.cardTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        Button("ביטול") { composingKind = nil }
                            .font(Theme.Typography.captionEmphasis)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }

                    TextField(kind.detailPlaceholder, text: $composerDetail, axis: .vertical)
                        .lineLimit(2...4)
                        .font(Theme.Typography.body)
                        .multilineTextAlignment(.trailing)
                        .padding(Theme.Spacing.m)
                        .background(Theme.Palette.background)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))

                    // Live preview in the caregiver's language builds trust
                    // that the message actually gets across.
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("כך \(caregiverName) יראה את זה:")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(previewText(kind: kind))
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(Theme.Spacing.s)
                    .background(Theme.Palette.sage.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))

                    BeaconPrimaryButton(
                        title: "שמירת ההוראה",
                        systemImage: "checkmark",
                        isEnabled: kind != .custom || !composerDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        Task {
                            await viewModel.addInstruction(
                                kind: kind,
                                detail: composerDetail,
                                createdByName: environment.currentUser.displayName
                            )
                        }
                        composingKind = nil
                        composerDetail = ""
                    }
                }
            }
        }
    }

    private func previewText(kind: CaregiverInstructionKind) -> String {
        let title = kind.localizedTitle(for: caregiverLanguage)
        let detail = composerDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty { return title }
        return kind == .custom ? detail : "\(title): \(detail)"
    }

    // MARK: - Active instruction rows

    private func instructionRow(_ instruction: CaregiverInstruction) -> some View {
        BeaconCard {
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    Task { await viewModel.removeInstruction(instruction) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.coralAccent)
                        .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("מחיקת ההוראה")

                Spacer()

                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(instruction.kind.hebrewLabel)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Image(systemName: instruction.kind.iconSymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Palette.deepTeal)
                    }
                    if !instruction.detail.isEmpty {
                        Text(instruction.detail)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("CaregiverInstructionsSheet") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    let viewModel = CaregiverLayerViewModel(context: container.mainContext)
    Task { await viewModel.activateCaregiver(name: "Maria", relationTitle: "מטפלת סיעודית", language: .tagalog) }
    return CaregiverInstructionsSheet(viewModel: viewModel)
        .modelContainer(container)
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
#endif

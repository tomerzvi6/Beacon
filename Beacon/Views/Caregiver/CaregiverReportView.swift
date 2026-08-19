import SwiftUI

/// Focused, kiosk-style reporting screen for the home caregiver.
/// Localized to the caregiver's language, large buttons, minimal text.
/// Intentionally NOT RTL — all supported caregiver languages are LTR;
/// direction follows `CaregiverLanguage.isRightToLeft`.
struct CaregiverReportView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: CaregiverLayerViewModel

    @State private var language: CaregiverLanguage = .english
    @State private var mealStatus: CaregiverMealStatus = .ateWell
    @State private var hydrationStatus: CaregiverHydrationStatus = .drankEnough
    @State private var sleepStatus: CaregiverSleepStatus = .sleptWell
    @State private var painLevel: Int = 0
    @State private var nauseaLevel: Int = 0
    @State private var fatigueLevel: Int = 0
    @State private var medicationStatus: CaregiverMedicationStatus = .taken
    @State private var freeText: String = ""
    @State private var isSubmitting = false
    @State private var showingThanks = false

    private var strings: CaregiverStrings { CaregiverStrings.strings(for: language) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    if !viewModel.activeInstructions.isEmpty {
                        instructionsSection
                    }

                    choiceSection(
                        title: strings.mealSection,
                        options: CaregiverMealStatus.allCases,
                        selection: $mealStatus,
                        label: mealLabel,
                        icon: \.iconSymbol
                    )
                    choiceSection(
                        title: strings.hydrationSection,
                        options: CaregiverHydrationStatus.allCases,
                        selection: $hydrationStatus,
                        label: hydrationLabel,
                        icon: \.iconSymbol
                    )
                    choiceSection(
                        title: strings.sleepSection,
                        options: CaregiverSleepStatus.allCases,
                        selection: $sleepStatus,
                        label: sleepLabel,
                        icon: \.iconSymbol
                    )

                    levelSection(title: strings.painSection, icon: "bolt.heart.fill", level: $painLevel)
                    levelSection(title: strings.nauseaSection, icon: "face.dashed", level: $nauseaLevel)
                    levelSection(title: strings.fatigueSection, icon: "moon.fill", level: $fatigueLevel)

                    choiceSection(
                        title: strings.medicationSection,
                        options: CaregiverMedicationStatus.allCases,
                        selection: $medicationStatus,
                        label: medicationLabel,
                        icon: \.iconSymbol
                    )

                    noteSection
                    submitButton
                }
                .padding(Theme.Spacing.m)
            }
            .beaconScreenBackground()
            .navigationTitle(strings.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(strings.closeButton) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    languagePicker
                }
            }
            .alert(strings.submittedTitle, isPresented: $showingThanks) {
                Button(strings.closeButton) { dismiss() }
            } message: {
                Text(strings.submittedMessage)
            }
        }
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        .onAppear {
            language = viewModel.activeCaregiver?.preferredLanguage ?? .english
        }
    }

    // MARK: - Header / language

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Palette.deepTeal)
            Text(strings.greeting)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
        }
    }

    private var languagePicker: some View {
        Menu {
            ForEach(CaregiverLanguage.allCases) { lang in
                Button {
                    language = lang
                } label: {
                    if lang == language {
                        Label(lang.nativeName, systemImage: "checkmark")
                    } else {
                        Text(lang.nativeName)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "globe")
                Text(language.nativeName)
                    .font(Theme.Typography.captionEmphasis)
            }
        }
    }

    // MARK: - Instructions from the family (caregiver's language)

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.coralAccent)
                Text(CaregiverInstructionKind.sectionHeader(for: language))
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(viewModel.activeInstructions) { instruction in
                    HStack(alignment: .top, spacing: Theme.Spacing.s) {
                        Image(systemName: instruction.kind.iconSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Palette.deepTeal)
                            .frame(width: Theme.Spacing.l)
                        Text(localizedInstructionText(instruction))
                            .font(Theme.Typography.bodyLarge)
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Palette.coralBackground.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            .beaconCardShadow()
        }
    }

    private func localizedInstructionText(_ instruction: CaregiverInstruction) -> String {
        let title = instruction.kind.localizedTitle(for: language)
        let detail = instruction.detail
        if detail.isEmpty { return title }
        return instruction.kind == .custom ? detail : "\(title): \(detail)"
    }

    // MARK: - Choice rows (big buttons)

    private func choiceSection<Option: Identifiable & Equatable>(
        title: String,
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String,
        icon: KeyPath<Option, String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            HStack(spacing: Theme.Spacing.s) {
                ForEach(options) { option in
                    bigOptionButton(
                        text: label(option),
                        systemImage: option[keyPath: icon],
                        isSelected: selection.wrappedValue == option
                    ) {
                        selection.wrappedValue = option
                    }
                }
            }
        }
    }

    private func bigOptionButton(
        text: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                Text(text)
                    .font(Theme.Typography.captionEmphasis)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Layout.floatingActionButtonSize + Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .padding(.horizontal, Theme.Spacing.xs)
            .foregroundStyle(isSelected ? .white : Theme.Palette.textPrimary)
            .background(isSelected ? Theme.Palette.deepTeal : Theme.Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            .beaconCardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 0–10 level rows

    private func levelSection(title: String, icon: String, level: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Palette.deepTeal)
                Text(title)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("\(level.wrappedValue)/10")
                    .font(Theme.Typography.timeLabel)
                    .foregroundStyle(level.wrappedValue >= 7
                                     ? Theme.Palette.coralAccent
                                     : Theme.Palette.textPrimary)
            }
            HStack(spacing: Theme.Spacing.m) {
                Text(strings.levelNone)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Slider(
                    value: Binding(
                        get: { Double(level.wrappedValue) },
                        set: { level.wrappedValue = Int($0.rounded()) }
                    ),
                    in: 0...10,
                    step: 1
                )
                .tint(level.wrappedValue >= 7 ? Theme.Palette.coralAccent : Theme.Palette.deepTeal)
                Text(strings.levelSevere)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            .beaconCardShadow()
        }
    }

    // MARK: - Free note + submit

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(strings.noteSection)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            TextField(strings.notePlaceholder, text: $freeText, axis: .vertical)
                .lineLimit(3...6)
                .font(Theme.Typography.bodyLarge)
                .padding(Theme.Spacing.m)
                .background(Theme.Palette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
                .beaconCardShadow()
        }
    }

    private var submitButton: some View {
        BeaconPrimaryButton(
            title: strings.submitButton,
            systemImage: "paperplane.fill",
            isEnabled: !isSubmitting
        ) {
            Task { await submit() }
        }
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.xl)
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        if language != viewModel.activeCaregiver?.preferredLanguage {
            await viewModel.updateLanguage(language)
        }

        let trimmedNote = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = CaregiverCheckInDraft(
            mealStatus: mealStatus,
            hydrationStatus: hydrationStatus,
            sleepStatus: sleepStatus,
            painLevel: painLevel,
            nauseaLevel: nauseaLevel,
            fatigueLevel: fatigueLevel,
            medicationStatus: medicationStatus,
            medicationNote: nil,
            freeTextOriginal: trimmedNote.isEmpty ? nil : trimmedNote,
            originalLanguage: language
        )
        guard await viewModel.submitCheckIn(draft) != nil else { return }
        showingThanks = true
    }

    // MARK: - Localized option labels

    private func mealLabel(_ status: CaregiverMealStatus) -> String {
        switch status {
        case .ateWell:   return strings.ateWell
        case .ateLittle: return strings.ateLittle
        case .didNotEat: return strings.didNotEat
        }
    }

    private func hydrationLabel(_ status: CaregiverHydrationStatus) -> String {
        switch status {
        case .drankEnough: return strings.drankEnough
        case .drankLittle: return strings.drankLittle
        case .didNotDrink: return strings.didNotDrink
        }
    }

    private func sleepLabel(_ status: CaregiverSleepStatus) -> String {
        switch status {
        case .sleptWell:   return strings.sleptWell
        case .sleptPoorly: return strings.sleptPoorly
        }
    }

    private func medicationLabel(_ status: CaregiverMedicationStatus) -> String {
        switch status {
        case .taken:   return strings.medicationTaken
        case .missed:  return strings.medicationMissed
        case .notSure: return strings.medicationNotSure
        }
    }
}

#Preview("CaregiverReportView") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    let viewModel = CaregiverLayerViewModel(context: container.mainContext)
    Task { await viewModel.activateCaregiver(name: "Maria", relationTitle: "מטפלת סיעודית", language: .english) }
    return CaregiverReportView(viewModel: viewModel)
        .modelContainer(container)
}

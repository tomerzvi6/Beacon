import SwiftUI
import SwiftData

struct PermissionsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var editingMember: FamilyMember?
    @State private var showingInvite = false
    @State private var showingCaregiverSetup = false
    @State private var caregiverViewModel: CaregiverLayerViewModel?

    private var manageableMembers: [FamilyMember] {
        environment.members.filter { !$0.isPatient && !$0.hasFullAccess }
    }

    private var ownerMembers: [FamilyMember] {
        environment.members.filter { $0.isPatient }
    }

    private var fullAccessCaregivers: [FamilyMember] {
        environment.members.filter { !$0.isPatient && $0.hasFullAccess }
    }

    var body: some View {
        NavigationStack {
            List {
                ownerSection
                fullAccessSection
                membersSection
                if (environment.currentUser.isPatient || environment.currentUser.role == .admin),
                   environment.patientAuthorizationStatus == .pendingPatientConsent {
                    patientApprovalSection
                }
                if environment.canInviteMembers {
                    inviteSection
                }
                if environment.canManagePermissions {
                    homeCaregiverSection
                }
                accountSection
            }
            .navigationTitle("ניהול גישה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
            }
            .sheet(item: $editingMember) { member in
                MemberPermissionsEditor(member: member)
                    .environment(environment)
            }
            .sheet(isPresented: $showingInvite) {
                InviteSheet()
                    .environment(environment)
            }
            .sheet(isPresented: $showingCaregiverSetup) {
                if let caregiverViewModel {
                    CaregiverSetupSheet(viewModel: caregiverViewModel)
                }
            }
            .onAppear {
                if caregiverViewModel == nil {
                    caregiverViewModel = CaregiverLayerViewModel(context: modelContext)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var homeCaregiverSection: some View {
        Section {
            Button {
                caregiverViewModel?.refresh()
                showingCaregiverSetup = true
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "figure.2.arms.open")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(caregiverViewModel?.isCaregiverLayerActive == true
                             ? "מטפל/ת בבית — \(caregiverViewModel?.activeCaregiver?.displayName ?? "")"
                             : "הוספת מטפל/ת בבית")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.deepTeal)
                        Text(caregiverViewModel?.isCaregiverLayerActive == true
                             ? "שכבת המטפל/ת פעילה — לחצו לניהול או לדיווח"
                             : "מטפל/ת מדווח/ת בשפה שלו/ה, ואתם מקבלים תקציר בעברית")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    if caregiverViewModel?.isCaregiverLayerActive == true {
                        BeaconBadge(text: "פעיל", tone: .sage, leadingDot: true)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("מטפל/ת בבית")
        } footer: {
            Text("שכבה אופציונלית. למטפל/ת אין גישה לתיק הרפואי — רק מסך דיווח יומי פשוט.")
        }
    }

    private var ownerSection: some View {
        Section {
            ForEach(ownerMembers) { member in
                memberRow(member: member, badge: "בעל/ת התיק", tone: .softBlue)
            }
        } header: {
            Text("מטופל/ת — סמכות עליונה")
        } footer: {
            Text("למטופל/ת יש זכות וטו על הרשאות וגישה לתיק.")
        }
    }

    private var fullAccessSection: some View {
        Section {
            ForEach(fullAccessCaregivers) { member in
                if environment.currentUser.isPatient {
                    Button {
                        editingMember = member
                    } label: {
                        memberRow(member: member, badge: "גישה מלאה", tone: .sage, showChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    memberRow(member: member, badge: "גישה מלאה", tone: .sage)
                }
            }
        } header: {
            Text("מטפלים מורשים — גישה מלאה")
        } footer: {
            Text(environment.currentUser.isPatient ? "המטופל/ת יכול/ה להסיר גישה מלאה בכל רגע." : "רק המטופל/ת יכול/ה להסיר או לשנות מטפל עם גישה מלאה.")
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(manageableMembers) { member in
                Button {
                    editingMember = member
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        BeaconAvatar(
                            systemImage: member.avatarSymbol,
                            diameter: 36,
                            tint: Theme.Palette.sage.opacity(0.4),
                            foreground: Theme.Palette.sageDark
                        )
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(member.displayName)
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text(member.relation)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(AppModule.allCases) { module in
                                let level = member.role.accessLevel(for: module)
                                if level > .none {
                                    Image(systemName: module.iconSymbol)
                                        .font(.system(size: 11))
                                        .foregroundStyle(level == .readWrite
                                                         ? Theme.Palette.deepTeal
                                                         : Theme.Palette.textSecondary)
                                }
                            }
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("חברי משפחה — גישה מותאמת אישית")
        } footer: {
            Text("לחץ על שם כדי לערוך את ההרשאות שלו.")
        }
    }

    private var inviteSection: some View {
        Section {
            Button {
                showingInvite = true
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: environment.canAddCaregiver
                          ? "person.badge.plus"
                          : "person.3.sequence.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(environment.canAddCaregiver
                                         ? Theme.Palette.deepTeal
                                         : Theme.Palette.textSecondary)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("הזמן איש קשר חדש")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(environment.canAddCaregiver
                                             ? Theme.Palette.deepTeal
                                             : Theme.Palette.textSecondary)
                        Text("\(environment.caregiverCount)/\(AppEnvironment.maxCaregivers) מטפלים")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("הזמנה")
        } footer: {
            Text(environment.canAddCaregiver
                 ? "יצירת קישור הזמנה אישי. הנמען ילחץ עליו עם Beacon מותקן ויצורף אוטומטית."
                 : "הגעת למגבלת \(AppEnvironment.maxCaregivers) מטפלים ב-MVP.")
        }
    }

    private var patientApprovalSection: some View {
        Section {
            Button {
                environment.approvePatientConsent()
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(width: 36, height: 36)
                    Text("אשר בעלות וגישה לתיק")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.deepTeal)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } header: {
            Text("אישור מטופל")
        } footer: {
            Text("אישור זה הופך את המטופל/ת לסמכות העליונה על התיק.")
        }
    }

    private func memberRow(
        member: FamilyMember,
        badge: String? = nil,
        tone: BeaconBadge.Tone = .softBlue,
        showChevron: Bool = false
    ) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            BeaconAvatar(
                systemImage: member.avatarSymbol,
                diameter: 36,
                tint: Theme.Palette.deepTeal.opacity(0.15),
                foreground: Theme.Palette.deepTeal
            )
            VStack(alignment: .trailing, spacing: 2) {
                Text(member.displayName)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(member.relation)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            if let badge {
                BeaconBadge(text: badge, tone: tone)
            }
            if showChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var accountSection: some View {
        Section {
            #if DEBUG
            NavigationLink {
                DiagnosticView()
                    .environment(environment)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "stethoscope.circle")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                    Text("אבחון שרת")
                        .font(Theme.Typography.bodyEmphasis)
                }
                .padding(.vertical, 4)
            }
            #endif
            Button(role: .destructive) {
                Task {
                    await environment.signOut()
                    // Local care data (tasks/meds/doses/symptoms/feed) isn't
                    // tied to the backend session — wipe it so a different
                    // family signing into this device never sees the
                    // previous family's medical data.
                    MockDataSeeder.disableDemoData(in: modelContext)
                }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                    Text("התנתק")
                        .font(Theme.Typography.bodyEmphasis)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        } header: {
            Text("חשבון")
        }
    }
}

// MARK: - Per-member editor
private struct MemberPermissionsEditor: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    var member: FamilyMember

    private var activeMember: FamilyMember {
        environment.members.first { $0.id == member.id } ?? member
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        BeaconAvatar(
                            systemImage: activeMember.avatarSymbol,
                            diameter: 48,
                            tint: Theme.Palette.softBlue,
                            foreground: Theme.Palette.deepTeal
                        )
                        VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                            Text(activeMember.displayName)
                                .font(Theme.Typography.sectionTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text(activeMember.relation)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                if activeMember.hasFullAccess {
                    Section {
                        Label("למשתמש הזה יש גישה מלאה", systemImage: "shield.checkered")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.deepTeal)
                    } footer: {
                        Text("ב-MVP המטופל/ת יכול/ה להסיר את הגישה המלאה. שינוי גישה מלאה לרמות חלקיות יחובר בהמשך.")
                    }
                } else {
                    Section {
                        ForEach(AppModule.allCases) { module in
                            ModulePermissionRow(
                                module: module,
                                current: activeMember.role.accessLevel(for: module),
                                onChange: { newLevel in
                                    environment.updatePermissions(
                                        for: activeMember.id,
                                        module: module,
                                        level: newLevel
                                    )
                                }
                            )
                        }
                    } header: {
                        Text("הרשאות לפי תחום")
                    } footer: {
                        Text("צפייה ועריכה — יכול לבצע פעולות. צפייה בלבד — רואה מידע ללא שינוי. ללא גישה — המסך מציג הודעת חסימה.")
                    }
                }

                if environment.canManagePermissions && !activeMember.isPatient {
                    Section {
                        Button(role: .destructive) {
                            environment.revokeAccess(for: activeMember.id)
                            dismiss()
                        } label: {
                            Label("הסר גישה מיד", systemImage: "person.crop.circle.badge.xmark")
                        }
                    } footer: {
                        Text("ההסרה מיידית במכשיר הזה ונרשמת ב-audit log המקומי.")
                    }
                }

                if environment.currentUser.isPatient,
                   environment.patientAuthorizationStatus == .pendingPatientConsent {
                    Section {
                        Button {
                            environment.approvePatientConsent()
                            dismiss()
                        } label: {
                            Label("אשר בעלות על התיק", systemImage: "checkmark.shield.fill")
                        }
                    } footer: {
                        Text("אישור המטופל הוא היד האחרונה במודל ההרשאות.")
                    }
                }
            }
            .navigationTitle("הרשאות — \(activeMember.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Generates a real Supabase invite token and displays a shareable deep link.
private struct InviteSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode: String?
    @State private var expiresInMinutes: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                    if !environment.canAddCaregiver {
                        limitReachedContent
                    } else if isLoading {
                        loadingContent
                    } else if let code = inviteCode {
                        successContent(code: code)
                    } else if let error = errorMessage {
                        errorContent(error)
                    }
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("הזמנת מטפל/ת")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .task {
            guard environment.canAddCaregiver else { isLoading = false; return }
            await generateCode()
        }
    }

    // MARK: - States

    private var loadingContent: some View {
        VStack(spacing: Theme.Spacing.l) {
            ProgressView()
                .controlSize(.large)
                .padding(.top, Theme.Spacing.xxl)
            Text("מייצר קוד הזמנה…")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func successContent(code: String) -> some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Theme.Palette.deepTeal)
                .frame(maxWidth: .infinity)

            Text("קוד ההזמנה מוכן")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text("שלח/י את הקוד למטפל/ת. אחרי שיתקינו את Beacon ויתחברו, הם יזינו אותו במסך ההצטרפות — ויראו את אותו תיק רפואי כמוך.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.trailing)

            BeaconCard {
                VStack(spacing: Theme.Spacing.s) {
                    Text("קוד הצטרפות")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    // LTR so the digits never reorder inside the RTL layout.
                    Text(spacedCode(code))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(code.map(String.init).joined(separator: " "))
                    if expiresInMinutes > 0 {
                        Text("בתוקף ל־\(expiryDescription)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            ShareLink(item: "הצטרף/י למעגל הטיפול שלנו ב-Beacon. קוד ההצטרפות שלך: \(code)") {
                Label("שתף/י ב-WhatsApp / SMS", systemImage: "square.and.arrow.up")
                    .font(Theme.Typography.bodyEmphasis)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Layout.prominentControlVerticalPadding)
                    .foregroundStyle(.white)
                    .background(Theme.Palette.deepTeal)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                UIPasteboard.general.string = code
                didCopy = true
            } label: {
                Label(didCopy ? "הועתק ✓" : "העתק קוד", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .font(Theme.Typography.bodyEmphasis)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Layout.prominentControlVerticalPadding)
                    .foregroundStyle(Theme.Palette.deepTeal)
                    .background(Theme.Palette.deepTeal.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: didCopy)
        }
    }

    /// "483920" → "483 920" — easier to read aloud over the phone.
    private func spacedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }

    private var expiryDescription: String {
        let days = expiresInMinutes / (60 * 24)
        if days >= 1 { return days == 1 ? "יום אחד" : "\(days) ימים" }
        let hours = max(1, expiresInMinutes / 60)
        return hours == 1 ? "שעה" : "\(hours) שעות"
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.Palette.coralAccent)
                .frame(maxWidth: .infinity)
            Text("לא ניתן היה ליצור קוד")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.trailing)
            BeaconPrimaryButton(title: "נסה שוב", systemImage: "arrow.clockwise") {
                isLoading = true
                errorMessage = nil
                Task { await generateCode() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var limitReachedContent: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity)
            Text("הגעת למגבלת המטפלים")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("ב-MVP הגבלנו עד \(AppEnvironment.maxCaregivers) מטפלים. כדי להוסיף עוד, הסר גישה ממטפל קיים תחילה.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Code generation

    /// Asks the backend for the code. It has to be the backend and not
    /// Supabase: the medical vault is scoped by the backend's household, so a
    /// relative who joined anywhere else would open the app to an empty file.
    private func generateCode() async {
        guard environment.backendUser != nil else {
            errorMessage = "לא נמצא מידע על המשתמש. נסה/י להתחבר מחדש."
            isLoading = false
            return
        }
        do {
            let invite = try await HouseholdService().createCaregiverInvite()
            inviteCode = invite.code
            expiresInMinutes = invite.expiresInMinutes
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ModulePermissionRow: View {
    var module: AppModule
    var current: AccessLevel
    var onChange: (AccessLevel) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: module.iconSymbol)
                .font(.system(size: 16))
                .foregroundStyle(current == .none ? Theme.Palette.textSecondary : Theme.Palette.deepTeal)
                .frame(width: 28)
            Text(module.displayLabel)
                .font(Theme.Typography.body)
                .foregroundStyle(current == .none ? Theme.Palette.textSecondary : Theme.Palette.textPrimary)
            Spacer()
            Picker("", selection: Binding(get: { current }, set: { onChange($0) })) {
                ForEach(AccessLevel.allCases) { level in
                    Text(level.displayLabel).tag(level)
                }
            }
            .pickerStyle(.menu)
            .tint(current == .none ? Theme.Palette.textSecondary : Theme.Palette.deepTeal)
        }
    }
}

#Preview("PermissionsSettingsView") {
    PermissionsSettingsView()
        .modelContainer(MockDataSeeder.makeInMemoryPreviewContainer())
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
}

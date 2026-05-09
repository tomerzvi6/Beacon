import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var editingMember: FamilyMember?
    @State private var showingMockInvite = false

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
                if environment.currentUser.isPatient,
                   environment.patientAuthorizationStatus == .pendingPatientConsent {
                    patientApprovalSection
                }
                if environment.canInviteMembers {
                    inviteSection
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
            .sheet(isPresented: $showingMockInvite) {
                MockInviteSheet()
                    .environment(environment)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
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
                if environment.canAddCaregiver {
                    environment.recordMockInviteOpened()
                } else {
                    environment.recordMockInviteBlockedByLimit()
                }
                showingMockInvite = true
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("הזמן איש קשר חדש")
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.deepTeal)
                        Text("\(environment.caregiverCount)/\(AppEnvironment.maxCaregivers) מטפלים")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    BeaconBadge(text: "Mock", tone: .neutral)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("הזמנה")
        } footer: {
            Text("כרגע זה מסך הדגמה בלבד. בהמשך ההזמנה תשלח קוד, והמטופל יאשר דרך מייל וצילום תעודת זהות.")
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
                Task { await environment.signOut() }
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

private struct MockInviteSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                    Image(systemName: environment.canAddCaregiver ? "person.badge.plus" : "person.3.sequence.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                        Text(environment.canAddCaregiver ? "הזמנה לדוגמה" : "הגעת למגבלת המטפלים")
                            .font(Theme.Typography.sectionTitle)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(message)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }

                    BeaconCard {
                        VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                            infoRow(icon: "number", title: "קוד הזמנה", value: environment.canAddCaregiver ? "MOCK-2481" : "לא זמין")
                            infoRow(icon: "envelope.fill", title: "אימות מטופל", value: "מייל לאימות")
                            infoRow(icon: "camera.viewfinder", title: "זיהוי", value: "צילום תעודת זהות")
                            infoRow(icon: "checkmark.shield.fill", title: "סמכות אחרונה", value: "אישור המטופל/ת")
                        }
                    }

                    BeaconSecondaryButton(title: "סגור") {
                        dismiss()
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle("הזמנת מטפל")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var message: String {
        if environment.canAddCaregiver {
            return "כרגע לא נשלחת הזמנה אמיתית. זה מדגים את ה-flow: מטפל מקבל קוד, המטופל מאמת מייל ותעודת זהות, ואז מאשר את הגישה."
        }
        return "ב-MVP הגבלנו עד \(AppEnvironment.maxCaregivers) מטפלים כדי לשמור על שליטה והרשאות פשוטות."
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.deepTeal)
                .frame(width: 30, height: 30)
                .background(Theme.Palette.softBlue.opacity(0.4))
                .clipShape(Circle())
            VStack(alignment: .trailing, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text(value)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            Spacer()
        }
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
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
}

import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var editingMember: FamilyMember?

    private var manageableMembers: [FamilyMember] {
        environment.members.filter { !$0.isPatient && !$0.isAdmin }
    }

    private var adminMembers: [FamilyMember] {
        environment.members.filter { $0.isAdmin }
    }

    var body: some View {
        NavigationStack {
            List {
                adminSection
                membersSection
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
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var adminSection: some View {
        Section {
            ForEach(adminMembers) { member in
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
                    BeaconBadge(text: "Admin", tone: .softBlue)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("מנהלים — גישה מלאה")
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
                // TODO: invite flow
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.deepTeal)
                        .frame(width: 36, height: 36)
                    Text("הזמן איש קשר חדש")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.deepTeal)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("הזמנה")
        }
    }

    private var accountSection: some View {
        Section {
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        BeaconAvatar(
                            systemImage: member.avatarSymbol,
                            diameter: 48,
                            tint: Theme.Palette.softBlue,
                            foreground: Theme.Palette.deepTeal
                        )
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(member.displayName)
                                .font(Theme.Typography.sectionTitle)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text(member.relation)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(AppModule.allCases) { module in
                        ModulePermissionRow(
                            module: module,
                            current: member.role.accessLevel(for: module),
                            onChange: { newLevel in
                                environment.updatePermissions(
                                    for: member.id,
                                    module: module,
                                    level: newLevel
                                )
                            }
                        )
                    }
                } header: {
                    Text("הרשאות לפי תחום")
                } footer: {
                    Text("צפייה ועריכה — יכול לבצע פעולות. צפייה בלבד — רואה מידע ללא שינוי. ללא גישה — הטאב מוסתר.")
                }

                if environment.canInviteMembers {
                    Section {
                        Button(role: .destructive) {
                            // TODO: promote to admin flow
                        } label: {
                            Label("הפוך ל-Admin", systemImage: "shield.fill")
                        }
                    }
                }
            }
            .navigationTitle("הרשאות — \(member.displayName)")
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

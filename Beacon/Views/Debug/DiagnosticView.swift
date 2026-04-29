import SwiftUI

/// Debug-only view that probes the Beacon Parser API to verify the
/// foundation layer end-to-end. Reachable from `PermissionsSettingsView →
/// אבחון שרת` (debug builds only).
struct DiagnosticView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var healthStatus: ProbeStatus = .idle
    @State private var membersStatus: ProbeStatus = .idle
    @State private var lastError: String?

    var body: some View {
        Form {
            backendSection
            tokenSection
            probesSection
            if let lastError {
                Section("שגיאה אחרונה") {
                    Text(lastError)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("אבחון שרת")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var backendSection: some View {
        Section("שרת") {
            LabeledContent("BACKEND_URL") {
                Text(APIConfig.baseURL.absoluteString)
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.trailing)
            }
            if APIConfig.isUsingDefaultLocalhost {
                Label(
                    "ברירת מחדל — Simulator בלבד. עדכן Secrets.plist למכשיר אמיתי.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private var tokenSection: some View {
        Section("אסימון Beacon") {
            LabeledContent("מצב") {
                Text(tokenSummary)
                    .font(.caption.monospaced())
            }
            if let user = environment.backendUser {
                LabeledContent("משתמש", value: user.full_name)
                LabeledContent("תפקיד", value: user.role)
                LabeledContent("household_id") {
                    Text(user.household_id.uuidString.prefix(8) + "…")
                        .font(.caption.monospaced())
                }
            }
            if let msg = environment.backendAuthErrorMessage {
                Text(msg)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
            }
        }
    }

    private var probesSection: some View {
        Section("בדיקות") {
            ProbeRow(
                title: "GET /health",
                status: healthStatus,
                action: { Task { await pingHealth() } }
            )
            ProbeRow(
                title: "GET /v1/households/members",
                status: membersStatus,
                action: { Task { await fetchMembers() } }
            )
        }
    }

    // MARK: - Helpers

    private var tokenSummary: String {
        guard let token = TokenStore.read() else { return "ללא אסימון" }
        let preview = String(token.prefix(12)) + "…"
        guard let exp = TokenStore.expirationDate(of: token) else { return preview }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(preview)  exp=\(formatter.string(from: exp))"
    }

    @MainActor
    private func pingHealth() async {
        healthStatus = .loading
        lastError = nil
        struct Health: Decodable {
            let status: String
            let service: String?
            let commit: String?
        }
        do {
            let h: Health = try await APIClient.shared.get("/health", authenticated: false)
            healthStatus = .success("\(h.status) — commit=\(h.commit ?? "—")")
        } catch let error as APIError {
            healthStatus = .failure
            lastError = error.diagnosticDescription
        } catch {
            healthStatus = .failure
            lastError = error.localizedDescription
        }
    }

    @MainActor
    private func fetchMembers() async {
        membersStatus = .loading
        lastError = nil
        do {
            let members: [BackendHouseholdMember] = try await APIClient.shared.get(
                "/v1/households/members"
            )
            let roles = members.map(\.role).joined(separator: ", ")
            membersStatus = .success("\(members.count) חברי משק־בית [\(roles)]")
        } catch let error as APIError {
            membersStatus = .failure
            lastError = error.diagnosticDescription
        } catch {
            membersStatus = .failure
            lastError = error.localizedDescription
        }
    }
}

// MARK: - Probe row

private enum ProbeStatus: Equatable {
    case idle
    case loading
    case success(String)
    case failure
}

private struct ProbeRow: View {
    let title: String
    let status: ProbeStatus
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.monospaced())
                Spacer()
                Button("הרץ", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(status == .loading)
            }
            switch status {
            case .idle:
                Text("—").font(.caption2).foregroundStyle(.secondary)
            case .loading:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("מריץ…") }
                    .font(.caption2)
            case .success(let detail):
                Label(detail, systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            case .failure:
                Label("נכשל — ראה שגיאה אחרונה", systemImage: "xmark.octagon.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

#if DEBUG
#Preview("DiagnosticView") {
    NavigationStack { DiagnosticView() }
        .environment(AppEnvironment())
        .environment(\.layoutDirection, .rightToLeft)
}
#endif

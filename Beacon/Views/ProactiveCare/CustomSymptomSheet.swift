import SwiftUI

struct CustomSymptomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var severity: Int = 3
    @State private var note: String = ""

    var onSave: (_ label: String, _ severity: Int, _ note: String?) -> Void

    private let severityLabels = ["קל מאוד", "קל", "בינוני", "חזק", "חזק מאוד"]

    var body: some View {
        NavigationStack {
            Form {
                Section("מה אתם מרגישים?") {
                    TextField("למשל: כאב ראש, סחרחורת, דפיקות לב", text: $label)
                        .font(Theme.Typography.body)
                }

                Section("עוצמה") {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                        HStack {
                            Spacer()
                            Text(severityLabels[severity - 1])
                                .font(Theme.Typography.bodyEmphasis)
                                .foregroundStyle(Theme.Palette.deepTeal)
                                .contentTransition(.numericText(value: Double(severity)))
                        }
                        Slider(
                            value: Binding(
                                get: { Double(severity) },
                                set: { severity = Int($0.rounded()) }
                            ),
                            in: 1...5,
                            step: 1
                        )
                        .tint(Theme.Palette.deepTeal)
                    }
                }

                Section("הערה (אופציונלי)") {
                    TextField("תיאור נוסף, נסיבות, מיקום...", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .font(Theme.Typography.body)
                }
            }
            .navigationTitle("מדד חדש")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמור") {
                        onSave(
                            label.trimmingCharacters(in: .whitespacesAndNewlines),
                            severity,
                            note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                        )
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#Preview("CustomSymptomSheet") {
    CustomSymptomSheet { _, _, _ in }
        .environment(\.locale, Locale(identifier: "he_IL"))
}

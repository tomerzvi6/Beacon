import SwiftUI
import SwiftData

struct CircleOfTrustView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: CircleOfTrustViewModel?
    @State private var toastMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                    if let vm = viewModel {
                        BeaconScreenHeader(
                            title: "מעגל תמיכה",
                            subtitle: "עדכונים על \(environment.patient.displayName) מהמשפחה."
                        )

                        if vm.canCompose {
                            ComposePostCard(
                                text: Binding(get: { vm.composerText }, set: { vm.composerText = $0 }),
                                status: Binding(get: { vm.composerStatus }, set: { vm.composerStatus = $0 }),
                                currentUser: environment.currentUser,
                                patient: environment.patient,
                                onPublish: {
                                    let hadText = !vm.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    let asPatient = vm.composerAsPatient && environment.currentUser.hasFullAccess
                                    Task {
                                        await vm.publishComposer()
                                        if hadText {
                                            toastMessage = asPatient
                                                ? "העדכון פורסם בשם \(environment.patient.displayName) ✓"
                                                : "העדכון פורסם ✓"
                                        }
                                    }
                                },
                                publishAsPatient: Binding(get: { vm.composerAsPatient }, set: { vm.composerAsPatient = $0 })
                            )
                        }

                        if vm.posts.isEmpty {
                            BeaconCard {
                                BeaconEmptyState(
                                    systemImage: "bubble.left.and.bubble.right",
                                    title: "אין עדכונים עדיין",
                                    message: vm.canCompose
                                        ? "פרסמו עדכון ראשון כדי לעדכן את המשפחה."
                                        : "כשיתקבל עדכון מהמטפל/ת הוא יופיע כאן."
                                )
                            }
                        } else {
                            VStack(spacing: Theme.Spacing.m) {
                                ForEach(vm.posts) { post in
                                    FeedPostCard(
                                        post: post,
                                        currentUser: environment.currentUser,
                                        onReact: { reaction in
                                            let wasReacted = post.myReactionsRaw.contains(reaction.rawValue)
                                            Task {
                                                await vm.toggleReaction(reaction, on: post)
                                                let emoji = reaction == .heart ? "❤" : "🤗"
                                                toastMessage = wasReacted ? "\(emoji) הוסר" : "\(emoji) נשלח"
                                            }
                                        },
                                        onAddComment: { body in
                                            Task {
                                                await vm.addComment(body, to: post)
                                                toastMessage = "תגובה נשלחה ✓"
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.top, Theme.Layout.scrollContentTopClearance)
                .padding(.bottom, Theme.Layout.scrollContentBottomClearance)
            }
        }
        .beaconScreenBackground()
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, Theme.Spacing.l)
                    .background(.regularMaterial, in: Capsule())
                    .beaconCardShadow()
                    .padding(.bottom, Theme.Spacing.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toastMessage)
        .sensoryFeedback(.impact(weight: .light), trigger: toastMessage)
        .task(id: toastMessage) {
            guard toastMessage != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            toastMessage = nil
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CircleOfTrustViewModel(context: context, environment: environment)
            } else {
                viewModel?.refresh()
            }
        }
        .onChange(of: environment.contentRevision) {
            viewModel?.refresh()
        }
        .task {
            await viewModel?.syncWithBackend()
        }
    }
}

#Preview("CircleOfTrustView") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    return CircleOfTrustView()
        .modelContainer(container)
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}

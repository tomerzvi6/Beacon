import SwiftUI
import SwiftData

struct FamilyScheduleCard: View {
    var events: [ScheduleEvent]

    var body: some View {
        BeaconCard {
            VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                BeaconSectionHeader(
                    title: "לוח זמנים משפחתי",
                    systemImage: "calendar"
                )

                if events.isEmpty {
                    Text("אין אירועים להיום.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .beaconHorizontalText()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(events) { event in
                            ScheduleEventRow(event: event)
                        }
                    }
                }
            }
        }
    }
}

#Preview("FamilyScheduleCard") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    let events = try! container.mainContext.fetch(
        FetchDescriptor<ScheduleEvent>(sortBy: [SortDescriptor(\.startsAt)])
    )
    return FamilyScheduleCard(events: events)
        .padding()
        .beaconScreenBackground()
        .modelContainer(container)
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}

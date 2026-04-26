import Foundation
import Observation
import SwiftData

@Observable
final class DashboardViewModel {
    private let context: ModelContext
    private let environment: AppEnvironment

    var events: [ScheduleEvent] = []
    var tasks: [DailyTask] = []

    init(context: ModelContext, environment: AppEnvironment) {
        self.context = context
        self.environment = environment
        refresh()
    }

    func refresh() {
        let eventDescriptor = FetchDescriptor<ScheduleEvent>(
            sortBy: [SortDescriptor(\.startsAt, order: .forward)]
        )
        let taskDescriptor = FetchDescriptor<DailyTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        events = (try? context.fetch(eventDescriptor)) ?? []
        tasks = (try? context.fetch(taskDescriptor)) ?? []
    }

    func claim(_ task: DailyTask) {
        task.claimedByMemberId = environment.currentUser.id
        save()
    }

    func release(_ task: DailyTask) {
        task.claimedByMemberId = nil
        save()
    }

    func toggleCompletion(_ task: DailyTask) {
        task.isCompleted.toggle()
        save()
    }

    private func save() {
        try? context.save()
        refresh()
    }
}

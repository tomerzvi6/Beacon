import Foundation
import Observation
import SwiftData

@Observable
final class DashboardViewModel {
    private let context: ModelContext
    private let environment: AppEnvironment
    private let taskService: TaskService
    private let scheduleService: ScheduleService

    var events: [ScheduleEvent] = []
    var tasks: [DailyTask] = []
    var isSyncing: Bool = false

    init(
        context: ModelContext,
        environment: AppEnvironment,
        taskService: TaskService = TaskService(),
        scheduleService: ScheduleService = ScheduleService()
    ) {
        self.context = context
        self.environment = environment
        self.taskService = taskService
        self.scheduleService = scheduleService
        refresh()
    }

    /// Fast local read — instant UI on appear, no network wait.
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

    /// Pulls tasks + schedule from the backend and reconciles them into
    /// local SwiftData (upsert by id, remove backend-known ids that no
    /// longer come back — e.g. a dismissed task). Call from `.task {}` on
    /// appear; `refresh()` already gave the UI something to show first.
    @MainActor
    func syncWithBackend() async {
        isSyncing = true
        defer { isSyncing = false }
        async let membersTask: Void = environment.refreshFamilyMembers()
        async let taskDTOs = fetchAllTasks()
        async let eventDTOs = try? scheduleService.list()

        let (fetchedTasks, fetchedEvents) = await (taskDTOs, eventDTOs)
        _ = await membersTask

        reconcileTasks(fetchedTasks)
        reconcileEvents(fetchedEvents ?? [])
        try? context.save()
        refresh()
    }

    private func fetchAllTasks() async -> [TaskService.TaskDTO] {
        async let approved = try? taskService.list(status: "approved")
        async let done = try? taskService.list(status: "done")
        return (await approved ?? []) + (await done ?? [])
    }

    private func reconcileTasks(_ dtos: [TaskService.TaskDTO]) {
        let fetchedIds = Set(dtos.map { $0.id.uuidString })
        for dto in dtos { upsertLocalTask(from: dto) }
        removeStale(DailyTask.self, keeping: fetchedIds) { $0.id }
    }

    private func reconcileEvents(_ dtos: [ScheduleService.EventDTO]) {
        let fetchedIds = Set(dtos.map { $0.id.uuidString })
        for dto in dtos { upsertLocalEvent(from: dto) }
        removeStale(ScheduleEvent.self, keeping: fetchedIds) { $0.id }
    }

    @discardableResult
    private func upsertLocalTask(from dto: TaskService.TaskDTO) -> DailyTask {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<DailyTask> { $0.id == targetId }
        let task = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: predicate)))?.first
            ?? {
                let created = DailyTask(id: targetId, title: dto.titleHe, kind: .logistics)
                context.insert(created)
                return created
            }()
        task.title = dto.titleHe
        task.detail = dto.descriptionHe
        task.kind = TaskKind(rawValue: dto.kind) ?? .logistics
        task.origin = TaskOrigin(rawValue: dto.origin) ?? .manual
        task.claimedByMemberId = dto.claimedBy?.uuidString
        task.isCompleted = (dto.status == "done")
        task.dueAt = dto.dueAt
        task.createdAt = dto.createdAt
        return task
    }

    @discardableResult
    private func upsertLocalEvent(from dto: ScheduleService.EventDTO) -> ScheduleEvent {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<ScheduleEvent> { $0.id == targetId }
        let event = (try? context.fetch(FetchDescriptor<ScheduleEvent>(predicate: predicate)))?.first
            ?? {
                let created = ScheduleEvent(
                    id: targetId, title: dto.title, startsAt: dto.startsAt,
                    kind: ScheduleEventKind(rawValue: dto.kind) ?? .routine
                )
                context.insert(created)
                return created
            }()
        event.title = dto.title
        event.startsAt = dto.startsAt
        event.kind = ScheduleEventKind(rawValue: dto.kind) ?? .routine
        event.locationName = dto.locationName
        event.companionMemberId = dto.companionUserId?.uuidString
        event.subtitle = dto.subtitle
        return event
    }

    /// Deletes local rows whose id round-trips as a UUID (i.e. came from a
    /// prior backend sync) but is no longer in the latest fetch — a
    /// dismissed task, deleted event, etc. Anything with a non-UUID id
    /// (shouldn't exist once synced, but costs nothing to leave alone) is
    /// left untouched.
    private func removeStale<T: PersistentModel>(
        _ type: T.Type, keeping fetchedIds: Set<String>, idOf: (T) -> String
    ) {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in all where UUID(uuidString: idOf(item)) != nil && !fetchedIds.contains(idOf(item)) {
            context.delete(item)
        }
    }

    // MARK: - Task writes (backend first, then mirror locally)

    @MainActor
    func claim(_ task: DailyTask) async {
        guard let id = UUID(uuidString: task.id) else { return }
        if let dto = try? await taskService.claim(taskId: id) {
            upsertLocalTask(from: dto)
        } else {
            task.claimedByMemberId = environment.currentUser.id  // offline-friendly fallback
        }
        save()
    }

    @MainActor
    func release(_ task: DailyTask) async {
        guard let id = UUID(uuidString: task.id) else { return }
        if let dto = try? await taskService.unclaim(taskId: id) {
            upsertLocalTask(from: dto)
        } else {
            task.claimedByMemberId = nil
        }
        save()
    }

    @MainActor
    func toggleCompletion(_ task: DailyTask) async {
        guard let id = UUID(uuidString: task.id) else { return }
        let dto = task.isCompleted
            ? try? await taskService.reopen(taskId: id)
            : try? await taskService.complete(taskId: id)
        if let dto {
            upsertLocalTask(from: dto)
        } else {
            task.isCompleted.toggle()
        }
        save()
    }

    private func save() {
        try? context.save()
        refresh()
    }
}

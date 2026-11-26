import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class PersonalReminders {
    static let shared = PersonalReminders()
    private static let prefix = "glimmer.personal-todo."
    private let center = UNUserNotificationCenter.current()
    private let delegate = ForegroundReminders()
    private var next: [PersonalTodo]?
    private var reconciling = false
    private(set) var schedulingFailed = false
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private init() {
        center.delegate = delegate
    }

    /// Ask only after a person saves a reminder in the app.
    func authorize() async -> Bool {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
            authorization = await center.notificationSettings().authorizationStatus
            return granted
        }
        return Self.allowsNotifications(settings.authorizationStatus)
    }

    func refresh(_ tasks: [PersonalTodo]) {
        next = tasks
        guard !reconciling else { return }
        reconciling = true
        Task {
            while let tasks = next {
                next = nil
                await reconcile(tasks)
            }
            reconciling = false
        }
    }

    nonisolated static func upcoming(_ tasks: [PersonalTodo], now: Date, limit: Int) -> [PersonalTodo] {
        tasks.filter { task in
            !task.completed && (task.reminderAt.map { $0 > now } ?? false)
        }
        .sorted { ($0.reminderAt ?? .distantFuture, $0.id.uuidString) < ($1.reminderAt ?? .distantFuture, $1.id.uuidString) }
        .prefix(max(0, limit))
        .map { $0 }
    }

    private static func allowsNotifications(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    private func reconcile(_ tasks: [PersonalTodo]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(Self.prefix) }
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        let limit = Self.allowsNotifications(settings.authorizationStatus) ? 60 - (pending.count - ours.count) : 0
        let wanted = Self.upcoming(tasks, now: .now, limit: limit)
        let identifiers = Set(wanted.map(identifier(for:)))
        let removals = ours.map(\.identifier).filter { !identifiers.contains($0) }
        if !removals.isEmpty { center.removePendingNotificationRequests(withIdentifiers: removals) }

        let openReminders = Set(tasks.filter { !$0.completed && $0.reminderAt != nil }.map(identifier(for:)))
        let delivered = await center.deliveredNotifications()
        let outdated = delivered.map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.prefix) && !openReminders.contains($0) }
        if !outdated.isEmpty { center.removeDeliveredNotifications(withIdentifiers: outdated) }

        var failed = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for task in wanted {
            guard let date = task.reminderAt else { continue }
            let matching = calendar.dateComponents(in: calendar.timeZone, from: date)
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = matching.year
            components.month = matching.month
            components.day = matching.day
            components.hour = matching.hour
            components.minute = matching.minute
            components.second = matching.second
            let id = identifier(for: task)
            if let existing = ours.first(where: { $0.identifier == id }),
               let trigger = existing.trigger as? UNCalendarNotificationTrigger,
               trigger.dateComponents == components, existing.content.body == task.title { continue }
            let content = UNMutableNotificationContent()
            content.title = "Glimmer reminder"
            content.body = task.title
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            guard trigger.nextTriggerDate() != nil else { continue }
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            } catch {
                failed = true
            }
        }
        schedulingFailed = failed
    }

    private func identifier(for task: PersonalTodo) -> String { Self.prefix + task.id.uuidString }
}

private final class ForegroundReminders: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

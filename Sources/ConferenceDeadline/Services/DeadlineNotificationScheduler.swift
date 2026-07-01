import Foundation

@MainActor
protocol DeadlineNotificationCenterAdapting: AnyObject {
    var isAvailable: Bool { get }
    func authorizationStatus() async -> NotificationPermission
    func requestAuthorization() async -> NotificationPermission
    var pendingIDs: Set<String> { get async }
    func add(_ notification: DeadlineNotification) async throws
    func removePending(withIDs ids: Set<String>) async
    func removeAllPending() async
    func openSystemSettings()
}

@MainActor
final class ReconciledDeadlineNotificationScheduler: DeadlineNotificationScheduling {
    private let center: DeadlineNotificationCenterAdapting

    init(center: DeadlineNotificationCenterAdapting) {
        self.center = center
    }

    var isAvailable: Bool { center.isAvailable }

    func authorizationStatus() async -> NotificationPermission {
        await center.authorizationStatus()
    }

    func requestAuthorization() async -> NotificationPermission {
        await center.requestAuthorization()
    }

    func synchronize(_ plan: NotificationPlan) async throws {
        for notification in plan.notifications {
            try await center.add(notification)
        }

        let desiredIDs = Set(plan.notifications.map(\.id))
        let obsoleteIDs = await center.pendingIDs.subtracting(desiredIDs)
        if !obsoleteIDs.isEmpty {
            await center.removePending(withIDs: obsoleteIDs)
        }
    }

    func removeAllPending() async {
        await center.removeAllPending()
    }

    func openSystemSettings() {
        center.openSystemSettings()
    }
}

import XCTest
@testable import ConferenceDeadline

@MainActor
final class DeadlineNotificationSchedulerTests: XCTestCase {
    func testSuccessfulSynchronizationRemovesOnlyObsoleteNotifications() async throws {
        let keep = DeadlineNotification(
            id: "keep",
            title: "Keep",
            body: "Keep",
            triggerDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let obsolete = DeadlineNotification(
            id: "obsolete",
            title: "Obsolete",
            body: "Obsolete",
            triggerDate: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let new = DeadlineNotification(
            id: "new",
            title: "New",
            body: "New",
            triggerDate: Date(timeIntervalSince1970: 1_800_000_200)
        )
        let center = InMemoryDeadlineNotificationCenter(pending: [keep, obsolete])
        let scheduler = ReconciledDeadlineNotificationScheduler(center: center)

        try await scheduler.synchronize(
            NotificationPlan(notifications: [keep, new])
        )

        XCTAssertEqual(center.pendingIDs, [keep.id, new.id])
    }

    func testFailedSynchronizationPreservesExistingNotifications() async {
        let existing = DeadlineNotification(
            id: "existing",
            title: "Existing",
            body: "Existing",
            triggerDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let first = DeadlineNotification(
            id: "new-first",
            title: "First",
            body: "First",
            triggerDate: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let second = DeadlineNotification(
            id: "new-second",
            title: "Second",
            body: "Second",
            triggerDate: Date(timeIntervalSince1970: 1_800_000_200)
        )
        let center = InMemoryDeadlineNotificationCenter(
            pending: [existing],
            failingID: second.id
        )
        let scheduler = ReconciledDeadlineNotificationScheduler(center: center)

        do {
            try await scheduler.synchronize(
                NotificationPlan(notifications: [first, second])
            )
            XCTFail("Expected synchronization to fail")
        } catch {}

        XCTAssertEqual(center.pendingIDs, [existing.id, first.id])
    }
}

@MainActor
private final class InMemoryDeadlineNotificationCenter: DeadlineNotificationCenterAdapting {
    let isAvailable = true
    private(set) var pendingIDs: Set<String>
    private let failingID: String?

    init(pending: [DeadlineNotification], failingID: String? = nil) {
        pendingIDs = Set(pending.map(\.id))
        self.failingID = failingID
    }

    func authorizationStatus() async -> NotificationPermission {
        .authorized
    }

    func requestAuthorization() async -> NotificationPermission {
        .authorized
    }

    func add(_ notification: DeadlineNotification) async throws {
        if notification.id == failingID {
            throw NSError(domain: "DeadlineNotificationSchedulerTests", code: 1)
        }
        pendingIDs.insert(notification.id)
    }

    func removePending(withIDs ids: Set<String>) async {
        pendingIDs.subtract(ids)
    }

    func removeAllPending() async {
        pendingIDs.removeAll()
    }

    func openSystemSettings() {}
}

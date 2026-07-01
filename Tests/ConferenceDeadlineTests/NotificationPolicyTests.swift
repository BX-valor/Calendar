import XCTest
@testable import ConferenceDeadline

@MainActor
final class NotificationPolicyTests: XCTestCase {
    func testEnablingAuthorizedNotificationsSynchronizesCurrentPlan() async throws {
        let conference = makeConference()
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [conference]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: false)
        let scheduler = PolicyScheduler(permission: .authorized)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        await policy.setEnabled(true)

        XCTAssertEqual(policy.state, .enabled)
        XCTAssertTrue(policy.isEnabled)
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(
            scheduler.synchronizedPlan,
            NotificationPlan.make(
                conferences: [conference],
                relativeTo: Self.now,
                calendar: Self.calendar
            )
        )
    }

    func testActivationDisablesNotificationsWhenPermissionWasRevoked() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: true)
        let scheduler = PolicyScheduler(permission: .denied)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        await policy.applicationDidBecomeActive()

        XCTAssertEqual(policy.state, .permissionDenied)
        XCTAssertFalse(policy.isEnabled)
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(scheduler.removeAllPendingCount, 1)
    }

    func testDeniedPermissionReturnsToggleToOffWithoutSynchronizing() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: false)
        let scheduler = PolicyScheduler(permission: .notDetermined)
        scheduler.requestedPermission = .denied
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        await policy.setEnabled(true)

        XCTAssertEqual(policy.state, .permissionDenied)
        XCTAssertFalse(policy.isEnabled)
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(scheduler.requestAuthorizationCount, 1)
        XCTAssertNil(scheduler.synchronizedPlan)
        XCTAssertEqual(scheduler.removeAllPendingCount, 1)
    }

    func testStartupDoesNotRequestUndeterminedPermissionAutomatically() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: true)
        let scheduler = PolicyScheduler(permission: .notDetermined)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        await policy.applicationDidBecomeActive()

        XCTAssertEqual(policy.state, .disabled)
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(scheduler.requestAuthorizationCount, 0)
        XCTAssertEqual(scheduler.removeAllPendingCount, 1)
    }

    func testStoredPreferenceDoesNotSynchronizeBeforePermissionCheck() async throws {
        let conference = makeConference()
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [conference]),
            now: { Self.now },
            refreshInterval: nil
        )
        let scheduler = PolicyScheduler(permission: .authorized)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: PolicyPreferences(isEnabled: true),
            now: { Self.now },
            calendar: Self.calendar
        )
        var edited = conference
        edited.name = "CVPR Updated"

        XCTAssertEqual(catalog.save(edited), .committed)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(policy.state, .disabled)
        XCTAssertTrue(scheduler.synchronizedPlans.isEmpty)
    }

    func testReturningFromPermissionSettingsEnablesNotificationsAfterAuthorization() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: false)
        let scheduler = PolicyScheduler(permission: .denied)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )
        await policy.setEnabled(true)
        XCTAssertEqual(policy.state, .permissionDenied)

        policy.openSystemSettings()
        scheduler.permission = .authorized
        await policy.applicationDidBecomeActive()

        XCTAssertEqual(scheduler.openSystemSettingsCount, 1)
        XCTAssertEqual(policy.state, .enabled)
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertNotNil(scheduler.synchronizedPlan)
    }

    func testExternalAuthorizationClearsDeniedStateWithoutEnablingPreference() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: false)
        let scheduler = PolicyScheduler(permission: .denied)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )
        await policy.setEnabled(true)
        scheduler.permission = .authorized

        await policy.applicationDidBecomeActive()

        XCTAssertEqual(policy.state, .disabled)
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertNil(scheduler.synchronizedPlan)
    }

    func testEnabledPolicySynchronizesWhenNotificationPlanChanges() async throws {
        let conference = makeConference()
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [conference]),
            now: { Self.now },
            refreshInterval: nil
        )
        let scheduler = PolicyScheduler(permission: .authorized)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: PolicyPreferences(isEnabled: false),
            now: { Self.now },
            calendar: Self.calendar
        )
        await policy.setEnabled(true)
        var edited = conference
        edited.name = "CVPR Updated"

        XCTAssertEqual(catalog.save(edited), .committed)
        await waitUntil { scheduler.synchronizedPlans.count == 2 }

        XCTAssertEqual(scheduler.synchronizedPlans.count, 2)
        let updatedPlan = try XCTUnwrap(scheduler.synchronizedPlans.last)
        XCTAssertTrue(
            updatedPlan.notifications
                .allSatisfy { $0.body.contains("CVPR Updated") }
        )
    }

    func testEnabledPolicyIgnoresCatalogChangesOutsideNotificationPlan() async throws {
        let conference = makeConference()
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [conference]),
            now: { Self.now },
            refreshInterval: nil
        )
        let scheduler = PolicyScheduler(permission: .authorized)
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: PolicyPreferences(isEnabled: false),
            now: { Self.now },
            calendar: Self.calendar
        )
        await policy.setEnabled(true)
        var edited = conference
        edited.category = "AI"
        edited.location = "Vancouver"
        edited.tags.append("推荐")

        XCTAssertEqual(catalog.save(edited), .committed)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(scheduler.synchronizedPlans.count, 1)
    }

    func testDisablingDuringSynchronizationWinsOverStaleCompletion() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: false)
        let scheduler = BlockingPolicyScheduler()
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        let enableTask = Task { await policy.setEnabled(true) }
        await waitUntil { scheduler.synchronizationStarted }
        await policy.setEnabled(false)
        scheduler.finishSynchronization()
        await enableTask.value

        XCTAssertEqual(policy.state, .disabled)
        XCTAssertFalse(policy.isEnabled)
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(scheduler.removeAllPendingCount, 2)
    }

    func testActivationFromPermissionPromptDoesNotCancelEnablingIntent() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: false)
        let scheduler = BlockingAuthorizationPolicyScheduler()
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        let enableTask = Task { await policy.setEnabled(true) }
        await waitUntil { scheduler.authorizationRequestStarted }
        await policy.applicationDidBecomeActive()
        scheduler.finishAuthorization(permission: .authorized)
        await enableTask.value

        XCTAssertEqual(policy.state, .enabled)
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertNotNil(scheduler.synchronizedPlan)
    }

    func testOutOfOrderSynchronizationsConvergeOnLatestPlan() async throws {
        let conference = makeConference()
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [conference]),
            now: { Self.now },
            refreshInterval: nil
        )
        let scheduler = OutOfOrderPolicyScheduler()
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: PolicyPreferences(isEnabled: false),
            now: { Self.now },
            calendar: Self.calendar
        )
        await policy.setEnabled(true)

        var older = conference
        older.name = "Older"
        XCTAssertEqual(catalog.save(older), .committed)
        await waitUntil { scheduler.synchronizationCount == 2 }

        var latest = conference
        latest.name = "Latest"
        XCTAssertEqual(catalog.save(latest), .committed)
        await waitUntil { scheduler.synchronizationCount == 3 }

        scheduler.finishSynchronization(id: 3)
        await waitUntil { scheduler.appliedPlan?.notifications.first?.body.contains("Latest") == true }
        scheduler.finishSynchronization(id: 2)
        await waitUntil { scheduler.synchronizationCount == 4 }
        scheduler.finishSynchronization(id: 4)
        await waitUntil { policy.state == .enabled }

        XCTAssertEqual(scheduler.synchronizationCount, 4)
        XCTAssertTrue(
            scheduler.appliedPlan?.notifications
                .allSatisfy { $0.body.contains("Latest") } == true
        )
    }

    func testUnavailableEnvironmentClearsEnabledPreference() throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: true)
        let scheduler = PolicyScheduler(permission: .authorized)
        scheduler.isAvailable = false

        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        XCTAssertEqual(policy.state, .unavailable)
        XCTAssertFalse(policy.isEnabled)
        XCTAssertFalse(preferences.isEnabled)
    }

    func testSynchronizationFailureKeepsEnabledPreferenceAndCanRetry() async throws {
        let catalog = try ConferenceCatalog(
            persistence: PolicyCatalogPersistence(defaults: [makeConference()]),
            now: { Self.now },
            refreshInterval: nil
        )
        let preferences = PolicyPreferences(isEnabled: false)
        let scheduler = PolicyScheduler(permission: .authorized)
        scheduler.synchronizationError = NSError(
            domain: "NotificationPolicyTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "通知中心暂不可用"]
        )
        let policy = NotificationPolicy(
            catalog: catalog,
            scheduler: scheduler,
            preferences: preferences,
            now: { Self.now },
            calendar: Self.calendar
        )

        await policy.setEnabled(true)

        XCTAssertEqual(policy.state, .syncFailed("通知中心暂不可用"))
        XCTAssertTrue(policy.isEnabled)
        XCTAssertTrue(preferences.isEnabled)

        scheduler.synchronizationError = nil
        await policy.retry()

        XCTAssertEqual(policy.state, .enabled)
        XCTAssertNotNil(scheduler.synchronizedPlan)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static var now: Date {
        calendar.date(
            from: DateComponents(year: 2027, month: 1, day: 1, hour: 12)
        )!
    }

    private func makeConference() -> Conference {
        let abstract = Self.calendar.date(
            from: DateComponents(year: 2027, month: 1, day: 8, hour: 23)
        )!
        return Conference(
            id: "cvpr2027",
            name: "CVPR",
            year: 2027,
            category: "CV",
            abstractDeadline: abstract,
            paperDeadline: abstract.addingTimeInterval(24 * 60 * 60),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil,
            location: nil,
            venue: nil,
            website: nil,
            timezone: "AoE",
            tags: ["CCF-A"]
        )
    }
}

private final class PolicyCatalogPersistence: ConferenceCatalogPersisting {
    let defaults: [Conference]

    init(defaults: [Conference]) {
        self.defaults = defaults
    }

    func load() throws -> ConferenceCatalogPersistenceState {
        ConferenceCatalogPersistenceState(
            defaults: defaults,
            userData: .empty,
            recovery: nil,
            isWriteEnabled: true
        )
    }

    func save(_ userData: ConferenceUserData) throws {}
}

private final class PolicyPreferences: NotificationPreferencePersisting {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }
}

@MainActor
private final class PolicyScheduler: DeadlineNotificationScheduling {
    var isAvailable = true
    var permission: NotificationPermission
    var requestedPermission: NotificationPermission?
    var synchronizationError: Error?
    private(set) var synchronizedPlan: NotificationPlan?
    private(set) var synchronizedPlans: [NotificationPlan] = []
    private(set) var removeAllPendingCount = 0
    private(set) var openSystemSettingsCount = 0
    private(set) var requestAuthorizationCount = 0

    init(permission: NotificationPermission) {
        self.permission = permission
    }

    func authorizationStatus() async -> NotificationPermission {
        return permission
    }

    func requestAuthorization() async -> NotificationPermission {
        requestAuthorizationCount += 1
        if let requestedPermission {
            permission = requestedPermission
        }
        return permission
    }

    func synchronize(_ plan: NotificationPlan) async throws {
        if let synchronizationError {
            throw synchronizationError
        }
        synchronizedPlan = plan
        synchronizedPlans.append(plan)
    }

    func removeAllPending() async {
        removeAllPendingCount += 1
    }

    func openSystemSettings() {
        openSystemSettingsCount += 1
    }
}

@MainActor
private final class BlockingPolicyScheduler: DeadlineNotificationScheduling {
    let isAvailable = true
    private(set) var synchronizationStarted = false
    private(set) var removeAllPendingCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> NotificationPermission {
        .authorized
    }

    func requestAuthorization() async -> NotificationPermission {
        .authorized
    }

    func synchronize(_ plan: NotificationPlan) async throws {
        synchronizationStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func removeAllPending() async {
        removeAllPendingCount += 1
    }

    func openSystemSettings() {}

    func finishSynchronization() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class BlockingAuthorizationPolicyScheduler: DeadlineNotificationScheduling {
    let isAvailable = true
    private(set) var authorizationRequestStarted = false
    private(set) var synchronizedPlan: NotificationPlan?
    private var continuation: CheckedContinuation<NotificationPermission, Never>?

    func authorizationStatus() async -> NotificationPermission {
        .notDetermined
    }

    func requestAuthorization() async -> NotificationPermission {
        authorizationRequestStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func synchronize(_ plan: NotificationPlan) async throws {
        synchronizedPlan = plan
    }

    func removeAllPending() async {}

    func openSystemSettings() {}

    func finishAuthorization(permission: NotificationPermission) {
        continuation?.resume(returning: permission)
        continuation = nil
    }
}

@MainActor
private final class OutOfOrderPolicyScheduler: DeadlineNotificationScheduling {
    private struct PendingSynchronization {
        let continuation: CheckedContinuation<Void, Never>
    }

    let isAvailable = true
    private(set) var synchronizationCount = 0
    private(set) var appliedPlan: NotificationPlan?
    private var pending: [Int: PendingSynchronization] = [:]

    func authorizationStatus() async -> NotificationPermission {
        .authorized
    }

    func requestAuthorization() async -> NotificationPermission {
        .authorized
    }

    func synchronize(_ plan: NotificationPlan) async throws {
        synchronizationCount += 1
        let id = synchronizationCount
        if id == 1 {
            appliedPlan = plan
            return
        }

        await withCheckedContinuation { continuation in
            pending[id] = PendingSynchronization(
                continuation: continuation
            )
        }
        appliedPlan = plan
    }

    func removeAllPending() async {}

    func openSystemSettings() {}

    func finishSynchronization(id: Int) {
        guard let synchronization = pending.removeValue(forKey: id) else { return }
        synchronization.continuation.resume()
    }
}

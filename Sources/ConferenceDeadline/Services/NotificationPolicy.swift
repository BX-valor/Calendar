import AppKit
import Combine
import Foundation

enum NotificationPermission: Equatable {
    case notDetermined
    case denied
    case authorized
}

enum NotificationPolicyState: Equatable {
    case unavailable
    case disabled
    case requestingPermission
    case syncing
    case enabled
    case permissionDenied
    case syncFailed(String)
}

protocol NotificationPreferencePersisting: AnyObject {
    var isEnabled: Bool { get set }
}

@MainActor
protocol DeadlineNotificationScheduling: AnyObject {
    var isAvailable: Bool { get }
    func authorizationStatus() async -> NotificationPermission
    func requestAuthorization() async -> NotificationPermission
    func synchronize(_ plan: NotificationPlan) async throws
    func removeAllPending() async
    func openSystemSettings()
}

@MainActor
final class NotificationPolicy: ObservableObject {
    @Published private(set) var state: NotificationPolicyState

    var isEnabled: Bool {
        switch state {
        case .requestingPermission, .syncing, .enabled, .syncFailed:
            return true
        case .unavailable, .disabled, .permissionDenied:
            return false
        }
    }

    private let catalog: ConferenceCatalog
    private let scheduler: DeadlineNotificationScheduling
    private let preferences: NotificationPreferencePersisting
    private let now: () -> Date
    private let calendar: Calendar
    private var shouldEnableAfterSettings = false
    private var currentPlan: NotificationPlan
    private var catalogCancellable: AnyCancellable?
    private var activationCancellable: AnyCancellable?
    private var operationGeneration: UInt = 0

    convenience init(catalog: ConferenceCatalog) {
        self.init(
            catalog: catalog,
            scheduler: ReconciledDeadlineNotificationScheduler(
                center: SystemDeadlineNotificationCenter()
            ),
            preferences: NotificationPreferences.shared
        )
        beginObservingApplicationActivation()
    }

    init(
        catalog: ConferenceCatalog,
        scheduler: DeadlineNotificationScheduling,
        preferences: NotificationPreferencePersisting,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.catalog = catalog
        self.scheduler = scheduler
        self.preferences = preferences
        self.now = now
        self.calendar = calendar
        currentPlan = NotificationPlan.make(
            conferences: catalog.snapshot.conferences,
            relativeTo: now(),
            calendar: calendar
        )
        state = scheduler.isAvailable ? .disabled : .unavailable
        if !scheduler.isAvailable {
            preferences.isEnabled = false
        }

        catalogCancellable = catalog.$snapshot
            .dropFirst()
            .sink { [weak self] snapshot in
                self?.catalogDidChange(snapshot)
            }
    }

    func setEnabled(_ enabled: Bool) async {
        let generation = beginOperation()
        guard scheduler.isAvailable else {
            preferences.isEnabled = false
            state = .unavailable
            return
        }

        guard enabled else {
            preferences.isEnabled = false
            state = .disabled
            await scheduler.removeAllPending()
            return
        }

        state = .requestingPermission
        var permission = await scheduler.authorizationStatus()
        guard isCurrent(generation) else { return }
        if permission == .notDetermined {
            permission = await scheduler.requestAuthorization()
            guard isCurrent(generation) else { return }
        }
        guard permission == .authorized else {
            preferences.isEnabled = false
            state = .permissionDenied
            await scheduler.removeAllPending()
            return
        }

        preferences.isEnabled = true
        await synchronizeCurrentPlan(generation: generation)
    }

    func retry() async {
        guard preferences.isEnabled, isEnabled else { return }
        let generation = beginOperation()
        await synchronizeCurrentPlan(generation: generation)
    }

    func applicationDidBecomeActive() async {
        guard state != .requestingPermission, state != .syncing else { return }
        let generation = beginOperation()
        guard scheduler.isAvailable else {
            preferences.isEnabled = false
            state = .unavailable
            return
        }
        let permission = await scheduler.authorizationStatus()
        guard isCurrent(generation) else { return }
        if shouldEnableAfterSettings {
            shouldEnableAfterSettings = false
            if permission == .authorized {
                preferences.isEnabled = true
                await synchronizeCurrentPlan(generation: generation)
            } else {
                state = .permissionDenied
            }
            return
        }
        guard preferences.isEnabled else {
            if state == .permissionDenied, permission != .denied {
                state = .disabled
            }
            return
        }

        guard permission == .authorized else {
            preferences.isEnabled = false
            state = permission == .denied ? .permissionDenied : .disabled
            await scheduler.removeAllPending()
            return
        }
        await synchronizeCurrentPlan(generation: generation)
    }

    func openSystemSettings() {
        if state == .permissionDenied {
            shouldEnableAfterSettings = true
        }
        scheduler.openSystemSettings()
    }

    private func synchronizeCurrentPlan(generation: UInt) async {
        currentPlan = NotificationPlan.make(
            conferences: catalog.snapshot.conferences,
            relativeTo: now(),
            calendar: calendar
        )
        await synchronize(currentPlan, generation: generation)
    }

    private func catalogDidChange(_ snapshot: ConferenceCatalogSnapshot) {
        let plan = NotificationPlan.make(
            conferences: snapshot.conferences,
            relativeTo: now(),
            calendar: calendar
        )
        guard plan != currentPlan else { return }
        currentPlan = plan
        guard preferences.isEnabled, isEnabled else { return }
        let generation = beginOperation()

        Task { [weak self] in
            await self?.synchronize(plan, generation: generation)
        }
    }

    private func synchronize(
        _ plan: NotificationPlan,
        generation: UInt
    ) async {
        state = .syncing
        do {
            try await scheduler.synchronize(plan)
            guard isCurrent(generation) else {
                await repairAfterStaleCompletion()
                return
            }
            state = .enabled
        } catch {
            guard isCurrent(generation) else {
                await repairAfterStaleCompletion()
                return
            }
            state = .syncFailed(error.localizedDescription)
        }
    }

    private func repairAfterStaleCompletion() async {
        if preferences.isEnabled {
            await synchronize(
                currentPlan,
                generation: operationGeneration
            )
        } else {
            await scheduler.removeAllPending()
        }
    }

    private func beginOperation() -> UInt {
        operationGeneration &+= 1
        return operationGeneration
    }

    private func isCurrent(_ generation: UInt) -> Bool {
        generation == operationGeneration
    }

    private func beginObservingApplicationActivation() {
        activationCancellable = NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )
        .sink { [weak self] _ in
            Task { await self?.applicationDidBecomeActive() }
        }

        Task { [weak self] in
            await self?.applicationDidBecomeActive()
        }
    }
}

import Combine
import Foundation

enum ConferenceCatalogRecovery: Equatable {
    case recovered(backupFileName: String)
    case writeBlocked(String)
}

enum ConferenceCatalogMutationResult: Equatable {
    case committed
    case validationFailed(Set<ConferenceValidationIssue>)
    case persistenceFailed(String)
    case writeBlockedByRecovery(String)
    case notFound
    case noChange
}

enum ConferenceValidationIssue: Hashable {
    case name
    case year
    case tags
    case deadline(DeadlineKind)
}

struct ConferenceCatalogSnapshot: Equatable {
    let conferences: [Conference]
    let hiddenDefaultConferences: [Conference]
    let recovery: ConferenceCatalogRecovery?
    let isWriteEnabled: Bool
}

struct ConferenceCatalogPersistenceState {
    let defaults: [Conference]
    let userData: ConferenceUserData
    let recovery: ConferenceCatalogRecovery?
    let isWriteEnabled: Bool
}

protocol ConferenceCatalogPersisting: AnyObject {
    func load() throws -> ConferenceCatalogPersistenceState
    func save(_ userData: ConferenceUserData) throws
}

@MainActor
protocol ConferenceCatalogClock: AnyObject {
    var now: Date { get }
    func start(_ onTick: @escaping () -> Void)
}

@MainActor
final class SystemConferenceCatalogClock: ConferenceCatalogClock {
    private let nowProvider: () -> Date
    private let refreshInterval: TimeInterval?
    private var timer: AnyCancellable?

    init(
        now: @escaping () -> Date = Date.init,
        refreshInterval: TimeInterval? = 60
    ) {
        nowProvider = now
        self.refreshInterval = refreshInterval
    }

    var now: Date { nowProvider() }

    func start(_ onTick: @escaping () -> Void) {
        guard let refreshInterval else { return }
        timer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in onTick() }
    }
}

@MainActor
final class ConferenceCatalog: ObservableObject {
    @Published private(set) var snapshot: ConferenceCatalogSnapshot

    private let persistence: ConferenceCatalogPersisting
    private let clock: ConferenceCatalogClock
    private let defaults: [Conference]
    private var userData: ConferenceUserData

    convenience init(
        persistence: ConferenceCatalogPersisting,
        now: @escaping () -> Date = Date.init,
        refreshInterval: TimeInterval? = 60
    ) throws {
        try self.init(
            persistence: persistence,
            clock: SystemConferenceCatalogClock(
                now: now,
                refreshInterval: refreshInterval
            )
        )
    }

    init(
        persistence: ConferenceCatalogPersisting,
        clock: ConferenceCatalogClock
    ) throws {
        let state = try persistence.load()
        self.persistence = persistence
        self.clock = clock
        defaults = state.defaults
        userData = state.userData
        snapshot = Self.makeSnapshot(
            defaults: state.defaults,
            userData: state.userData,
            recovery: state.recovery,
            isWriteEnabled: state.isWriteEnabled,
            relativeTo: clock.now
        )
        clock.start { [weak self] in
            self?.rebuildSnapshot()
        }
    }

    func save(_ conference: Conference) -> ConferenceCatalogMutationResult {
        if let blocked = writeBlockedResult() { return blocked }

        let issues = validationIssues(for: conference)
        guard issues.isEmpty else {
            return .validationFailed(issues)
        }

        var updatedUserData = userData
        if let defaultConference = defaults.first(where: { $0.id == conference.id }),
           defaultConference == conference {
            updatedUserData.conferences.removeAll { $0.id == conference.id }
        } else if let index = updatedUserData.conferences.firstIndex(where: { $0.id == conference.id }) {
            updatedUserData.conferences[index] = conference
        } else {
            updatedUserData.conferences.append(conference)
        }

        return commit(updatedUserData)
    }

    func delete(id: String) -> ConferenceCatalogMutationResult {
        if let blocked = writeBlockedResult() { return blocked }

        var updatedUserData = userData
        if defaults.contains(where: { $0.id == id }) {
            guard !updatedUserData.hiddenDefaultIDs.contains(id) else { return .noChange }
            updatedUserData.hiddenDefaultIDs.insert(id)
        } else if updatedUserData.conferences.contains(where: { $0.id == id }) {
            updatedUserData.conferences.removeAll { $0.id == id }
        } else {
            return .notFound
        }
        return commit(updatedUserData)
    }

    func restoreDefault(id: String) -> ConferenceCatalogMutationResult {
        if let blocked = writeBlockedResult() { return blocked }
        guard defaults.contains(where: { $0.id == id }) else { return .notFound }
        guard userData.hiddenDefaultIDs.contains(id) else { return .noChange }

        var updatedUserData = userData
        updatedUserData.hiddenDefaultIDs.remove(id)
        return commit(updatedUserData)
    }

    func restoreAllDefaults() -> ConferenceCatalogMutationResult {
        if let blocked = writeBlockedResult() { return blocked }
        guard !userData.hiddenDefaultIDs.isEmpty else { return .noChange }

        var updatedUserData = userData
        updatedUserData.hiddenDefaultIDs.removeAll()
        return commit(updatedUserData)
    }

    func dismissRecoveryNotice() {
        guard case .recovered = snapshot.recovery else { return }
        snapshot = ConferenceCatalogSnapshot(
            conferences: snapshot.conferences,
            hiddenDefaultConferences: snapshot.hiddenDefaultConferences,
            recovery: nil,
            isWriteEnabled: snapshot.isWriteEnabled
        )
    }

    func validationIssues(for conference: Conference) -> Set<ConferenceValidationIssue> {
        var issues: Set<ConferenceValidationIssue> = []
        if conference.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.insert(.name)
        }
        if conference.year <= 0 {
            issues.insert(.year)
        }
        if !conference.tags.contains(where: { ["CCF-A", "CCF-B", "CCF-C"].contains($0) }) {
            issues.insert(.tags)
        }
        for kind in conference.deadlineLifecycle.validationErrors.keys {
            issues.insert(.deadline(kind))
        }
        return issues
    }

    private func writeBlockedResult() -> ConferenceCatalogMutationResult? {
        guard !snapshot.isWriteEnabled else { return nil }
        if case .writeBlocked(let reason) = snapshot.recovery {
            return .writeBlockedByRecovery(reason)
        }
        return .writeBlockedByRecovery("Conference Catalog 当前不可写")
    }

    private func commit(_ updatedUserData: ConferenceUserData) -> ConferenceCatalogMutationResult {
        do {
            try persistence.save(updatedUserData)
        } catch {
            return .persistenceFailed(error.localizedDescription)
        }

        userData = updatedUserData
        rebuildSnapshot()
        return .committed
    }

    private func rebuildSnapshot() {
        snapshot = Self.makeSnapshot(
            defaults: defaults,
            userData: userData,
            recovery: snapshot.recovery,
            isWriteEnabled: snapshot.isWriteEnabled,
            relativeTo: clock.now
        )
    }

    private static func makeSnapshot(
        defaults: [Conference],
        userData: ConferenceUserData,
        recovery: ConferenceCatalogRecovery?,
        isWriteEnabled: Bool,
        relativeTo now: Date
    ) -> ConferenceCatalogSnapshot {
        var conferences = defaults.filter {
            !userData.hiddenDefaultIDs.contains($0.id)
        }
        for conference in userData.conferences {
            guard !userData.hiddenDefaultIDs.contains(conference.id) else { continue }
            if let index = conferences.firstIndex(where: { $0.id == conference.id }) {
                conferences[index] = conference
            } else {
                conferences.append(conference)
            }
        }
        conferences.sort {
            $0.deadlineLifecycle.summary(relativeTo: now).entry.date
                < $1.deadlineLifecycle.summary(relativeTo: now).entry.date
        }

        let hidden = defaults
            .filter { userData.hiddenDefaultIDs.contains($0.id) }
            .map { defaultConference in
                userData.conferences.first { $0.id == defaultConference.id } ?? defaultConference
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return ConferenceCatalogSnapshot(
            conferences: conferences,
            hiddenDefaultConferences: hidden,
            recovery: recovery,
            isWriteEnabled: isWriteEnabled
        )
    }
}

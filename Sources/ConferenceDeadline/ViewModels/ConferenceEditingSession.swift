import Combine
import Foundation

enum ConferenceEditingCommitResult: Equatable {
    case saved
    case savedWithNotificationWarning(String)
    case validationFailed
    case persistenceFailed(String)
    case noDraft
}

enum ConferenceEditingField: Hashable {
    case name
    case year
    case tags
    case deadline(DeadlineKind)
}

enum ConferenceEditingNavigationResult: Equatable {
    case completed
    case confirmationRequired
}

enum ConferenceEditingNavigation: Equatable {
    case selectConference(String)
    case newConference
    case exit
}

@MainActor
final class ConferenceEditingSession: ObservableObject {
    @Published private(set) var conferences: [Conference]
    @Published private(set) var selectedID: String?
    @Published private(set) var draft: Conference?
    @Published private(set) var validationErrors: [ConferenceEditingField: String] = [:]
    @Published private(set) var pendingNavigation: ConferenceEditingNavigation?
    @Published private(set) var exitRequested = false
    @Published private(set) var lastCommitResult: ConferenceEditingCommitResult?
    @Published private(set) var isCommitting = false

    var isDirty: Bool {
        draft != savedDraft
    }

    var hiddenDefaultConferences: [Conference] {
        defaults
            .filter { userData.hiddenDefaultIDs.contains($0.id) }
            .map { defaultConference in
                userData.conferences.first { $0.id == defaultConference.id } ?? defaultConference
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let store: ConferenceEditingStore
    private let notifications: ConferenceNotificationSynchronizing
    private let onConferencesChanged: ([Conference]) -> Void
    private let onCommitCompleted: (ConferenceEditingCommitResult) -> Void
    private let makeID: () -> String
    private let now: () -> Date
    private let defaults: [Conference]
    private var userData: ConferenceUserData
    private var savedDraft: Conference?
    private var selectionBeforeNew: String?

    init(
        store: ConferenceEditingStore,
        notifications: ConferenceNotificationSynchronizing,
        makeID: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = Date.init,
        onConferencesChanged: @escaping ([Conference]) -> Void = { _ in },
        onCommitCompleted: @escaping (ConferenceEditingCommitResult) -> Void = { _ in }
    ) throws {
        self.store = store
        self.notifications = notifications
        self.makeID = makeID
        self.now = now
        self.onConferencesChanged = onConferencesChanged
        self.onCommitCompleted = onCommitCompleted
        defaults = try store.loadDefaultConferences()
        userData = try store.loadUserData()
        conferences = Self.merge(defaults: defaults, userData: userData)
        selectedID = conferences.first?.id
        draft = conferences.first
        savedDraft = conferences.first
    }

    func updateDraft(_ conference: Conference) {
        guard conference.id == draft?.id else { return }
        draft = conference
        lastCommitResult = nil
        if !validationErrors.isEmpty {
            validationErrors = Self.validate(conference)
        }
    }

    func requestSelection(id: String) -> ConferenceEditingNavigationResult {
        guard id != selectedID else { return .completed }
        return requestNavigation(.selectConference(id))
    }

    func requestNewConference() -> ConferenceEditingNavigationResult {
        requestNavigation(.newConference)
    }

    func requestExit() -> ConferenceEditingNavigationResult {
        requestNavigation(.exit)
    }

    func cancelPendingNavigation() {
        pendingNavigation = nil
    }

    func discardChangesAndContinue() {
        guard let navigation = pendingNavigation else { return }
        discardChanges()
        pendingNavigation = nil
        perform(navigation)
    }

    func saveChangesAndContinue() async -> ConferenceEditingCommitResult {
        guard let navigation = pendingNavigation else { return .noDraft }
        let result = await save()
        pendingNavigation = nil
        if result.isSuccessful {
            perform(navigation)
            lastCommitResult = result
        }
        return result
    }

    private func beginNewConference() {
        selectionBeforeNew = selectedID
        let currentDate = now()
        let conference = Conference(
            id: makeID(),
            name: "",
            year: Calendar.current.component(.year, from: currentDate) + 1,
            category: nil,
            abstractDeadline: currentDate.addingTimeInterval(30 * 24 * 60 * 60),
            paperDeadline: currentDate.addingTimeInterval(37 * 24 * 60 * 60),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil,
            location: nil,
            venue: nil,
            website: nil,
            timezone: nil,
            tags: ["CCF-A"]
        )
        selectedID = conference.id
        savedDraft = nil
        draft = conference
        validationErrors = [:]
        lastCommitResult = nil
    }

    func discardChanges() {
        validationErrors = [:]
        lastCommitResult = nil
        if let savedDraft {
            draft = savedDraft
            return
        }

        let fallbackID = selectionBeforeNew ?? conferences.first?.id
        selectionBeforeNew = nil
        selectConference(id: fallbackID)
    }

    func deleteSelectedConference() async -> ConferenceEditingCommitResult {
        guard let selectedID else {
            lastCommitResult = .noDraft
            return .noDraft
        }

        var updatedUserData = userData
        if defaults.contains(where: { $0.id == selectedID }) {
            updatedUserData.hiddenDefaultIDs.insert(selectedID)
        } else {
            updatedUserData.conferences.removeAll { $0.id == selectedID }
        }

        return await commit(updatedUserData, preferredSelectedID: nil)
    }

    func restoreDefaultConference(id: String) async -> ConferenceEditingCommitResult {
        guard userData.hiddenDefaultIDs.contains(id) else {
            lastCommitResult = .noDraft
            return .noDraft
        }

        var updatedUserData = userData
        updatedUserData.hiddenDefaultIDs.remove(id)
        return await commit(updatedUserData, preferredSelectedID: selectedID ?? id)
    }

    func restoreAllDefaultConferences() async -> ConferenceEditingCommitResult {
        guard !userData.hiddenDefaultIDs.isEmpty else {
            lastCommitResult = .noDraft
            return .noDraft
        }

        var updatedUserData = userData
        updatedUserData.hiddenDefaultIDs.removeAll()
        return await commit(updatedUserData, preferredSelectedID: selectedID)
    }

    func save() async -> ConferenceEditingCommitResult {
        guard let draft else {
            lastCommitResult = .noDraft
            return .noDraft
        }

        validationErrors = Self.validate(draft)
        guard validationErrors.isEmpty else {
            lastCommitResult = .validationFailed
            return .validationFailed
        }

        var updatedUserData = userData
        if let defaultConference = defaults.first(where: { $0.id == draft.id }), defaultConference == draft {
            updatedUserData.conferences.removeAll { $0.id == draft.id }
        } else if let index = updatedUserData.conferences.firstIndex(where: { $0.id == draft.id }) {
            updatedUserData.conferences[index] = draft
        } else {
            updatedUserData.conferences.append(draft)
        }

        return await commit(updatedUserData, preferredSelectedID: draft.id)
    }

    private static func merge(
        defaults: [Conference],
        userData: ConferenceUserData
    ) -> [Conference] {
        userData.activeConferences(applyingTo: defaults)
    }

    private func selectConference(id: String?) {
        selectedID = id
        savedDraft = conferences.first { $0.id == id }
        draft = savedDraft
        validationErrors = [:]
        lastCommitResult = nil
    }

    private func requestNavigation(
        _ navigation: ConferenceEditingNavigation
    ) -> ConferenceEditingNavigationResult {
        if isDirty {
            pendingNavigation = navigation
            return .confirmationRequired
        }

        perform(navigation)
        return .completed
    }

    private func perform(_ navigation: ConferenceEditingNavigation) {
        switch navigation {
        case .selectConference(let id):
            selectConference(id: id)
        case .newConference:
            beginNewConference()
        case .exit:
            exitRequested = true
        }
    }

    private func commit(
        _ updatedUserData: ConferenceUserData,
        preferredSelectedID: String?
    ) async -> ConferenceEditingCommitResult {
        guard !isCommitting else { return .noDraft }
        isCommitting = true
        defer { isCommitting = false }

        do {
            try store.saveUserData(updatedUserData)
        } catch {
            let result = ConferenceEditingCommitResult.persistenceFailed(error.localizedDescription)
            return recordCommit(result)
        }

        userData = updatedUserData
        conferences = Self.merge(defaults: defaults, userData: userData)
        onConferencesChanged(conferences)
        let nextID = preferredSelectedID.flatMap { preferredID in
            conferences.contains(where: { $0.id == preferredID }) ? preferredID : nil
        } ?? conferences.first?.id
        selectionBeforeNew = nil
        selectConference(id: nextID)

        do {
            try await notifications.synchronize(conferences: conferences)
            return recordCommit(.saved)
        } catch {
            let result = ConferenceEditingCommitResult.savedWithNotificationWarning(
                error.localizedDescription
            )
            return recordCommit(result)
        }
    }

    private func recordCommit(
        _ result: ConferenceEditingCommitResult
    ) -> ConferenceEditingCommitResult {
        lastCommitResult = result
        onCommitCompleted(result)
        return result
    }

    private static func validate(_ conference: Conference) -> [ConferenceEditingField: String] {
        var errors: [ConferenceEditingField: String] = [:]

        if conference.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.name] = "会议名称不能为空"
        }
        if conference.year <= 0 {
            errors[.year] = "年份必须大于 0"
        }
        if !conference.tags.contains(where: { ["CCF-A", "CCF-B", "CCF-C"].contains($0) }) {
            errors[.tags] = "至少选择一个 CCF 评级标签"
        }

        for kind in conference.deadlineLifecycle.validationErrors.keys {
            errors[.deadline(kind)] = "日期不能早于前一个 Deadline"
        }

        return errors
    }
}

private extension ConferenceEditingCommitResult {
    var isSuccessful: Bool {
        switch self {
        case .saved, .savedWithNotificationWarning:
            return true
        case .validationFailed, .persistenceFailed, .noDraft:
            return false
        }
    }
}

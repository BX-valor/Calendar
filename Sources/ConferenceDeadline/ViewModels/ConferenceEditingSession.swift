import Combine
import Foundation

enum ConferenceEditingCommitResult: Equatable {
    case saved
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
    @Published private(set) var selectedID: String?
    @Published private(set) var draft: Conference?
    @Published private(set) var validationErrors: [ConferenceEditingField: String] = [:]
    @Published private(set) var pendingNavigation: ConferenceEditingNavigation?
    @Published private(set) var exitRequested = false
    @Published private(set) var lastCommitResult: ConferenceEditingCommitResult?
    @Published private(set) var isCommitting = false

    var conferences: [Conference] {
        catalog.snapshot.conferences
    }

    var hiddenDefaultConferences: [Conference] {
        catalog.snapshot.hiddenDefaultConferences
    }

    var isDirty: Bool {
        draft != savedDraft
    }

    private let catalog: ConferenceCatalog
    private let makeID: () -> String
    private let now: () -> Date
    private var savedDraft: Conference?
    private var selectionBeforeNew: String?
    private var catalogCancellable: AnyCancellable?

    init(
        catalog: ConferenceCatalog,
        makeID: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = Date.init
    ) {
        self.catalog = catalog
        self.makeID = makeID
        self.now = now

        let initial = catalog.snapshot.conferences.first
        selectedID = initial?.id
        draft = initial
        savedDraft = initial

        catalogCancellable = catalog.$snapshot
            .dropFirst()
            .sink { [weak self] snapshot in
                self?.catalogDidChange(snapshot)
            }
    }

    func updateDraft(_ conference: Conference) {
        guard conference.id == draft?.id else { return }
        draft = conference
        lastCommitResult = nil
        if !validationErrors.isEmpty {
            validationErrors = validationMessages(
                for: catalog.validationIssues(for: conference)
            )
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
            return recordCommit(.noDraft)
        }
        return await commit(preferredSelectedID: nil) {
            catalog.delete(id: selectedID)
        }
    }

    func restoreDefaultConference(id: String) async -> ConferenceEditingCommitResult {
        await commit(preferredSelectedID: selectedID ?? id) {
            catalog.restoreDefault(id: id)
        }
    }

    func restoreAllDefaultConferences() async -> ConferenceEditingCommitResult {
        await commit(preferredSelectedID: selectedID) {
            catalog.restoreAllDefaults()
        }
    }

    func save() async -> ConferenceEditingCommitResult {
        guard let draft else {
            return recordCommit(.noDraft)
        }
        return await commit(preferredSelectedID: draft.id) {
            catalog.save(draft)
        }
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
        preferredSelectedID: String?,
        mutation: () -> ConferenceCatalogMutationResult
    ) async -> ConferenceEditingCommitResult {
        guard !isCommitting else { return .noDraft }
        isCommitting = true
        defer { isCommitting = false }

        let mutationResult = mutation()
        switch mutationResult {
        case .validationFailed(let issues):
            validationErrors = validationMessages(for: issues)
            return recordCommit(.validationFailed)
        case .persistenceFailed(let message), .writeBlockedByRecovery(let message):
            return recordCommit(.persistenceFailed(message))
        case .notFound, .noChange:
            return recordCommit(.noDraft)
        case .committed:
            break
        }

        let nextID = preferredSelectedID.flatMap { preferredID in
            conferences.contains(where: { $0.id == preferredID }) ? preferredID : nil
        } ?? conferences.first?.id
        selectionBeforeNew = nil
        selectConference(id: nextID)
        return recordCommit(.saved)
    }

    private func catalogDidChange(_ snapshot: ConferenceCatalogSnapshot) {
        objectWillChange.send()
        guard !isDirty else { return }

        let next = snapshot.conferences.first { $0.id == selectedID }
            ?? snapshot.conferences.first
        selectedID = next?.id
        savedDraft = next
        draft = next
    }

    private func validationMessages(
        for issues: Set<ConferenceValidationIssue>
    ) -> [ConferenceEditingField: String] {
        var messages: [ConferenceEditingField: String] = [:]
        for issue in issues {
            switch issue {
            case .name:
                messages[.name] = "会议名称不能为空"
            case .year:
                messages[.year] = "年份必须大于 0"
            case .tags:
                messages[.tags] = "至少选择一个 CCF 评级标签"
            case .deadline(let kind):
                messages[.deadline(kind)] = "日期不能早于前一个 Deadline"
            }
        }
        return messages
    }

    private func recordCommit(
        _ result: ConferenceEditingCommitResult
    ) -> ConferenceEditingCommitResult {
        lastCommitResult = result
        return result
    }
}

private extension ConferenceEditingCommitResult {
    var isSuccessful: Bool {
        switch self {
        case .saved:
            return true
        case .validationFailed, .persistenceFailed, .noDraft:
            return false
        }
    }
}

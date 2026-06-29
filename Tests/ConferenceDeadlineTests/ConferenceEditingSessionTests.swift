import XCTest
@testable import ConferenceDeadline

@MainActor
final class ConferenceEditingSessionTests: XCTestCase {
    func testDraftChangesAreCommittedOnlyAfterSave() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let notifications = NoopConferenceNotificationSynchronizer()
        let session = try ConferenceEditingSession(store: store, notifications: notifications)

        var edited = try XCTUnwrap(session.draft)
        edited.name = "CVPR Updated"
        session.updateDraft(edited)

        XCTAssertEqual(session.conferences.map(\.name), ["CVPR"])
        let beforeSave = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertEqual(beforeSave.conferences.map(\.name), ["CVPR"])

        let result = await session.save()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(session.conferences.map(\.name), ["CVPR Updated"])
        let afterSave = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertEqual(afterSave.conferences.map(\.name), ["CVPR Updated"])
    }

    func testInvalidDraftCannotBeSaved() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )

        var invalid = try XCTUnwrap(session.draft)
        invalid.name = "  "
        invalid.tags = ["推荐"]
        invalid.abstractDeadline = invalid.paperDeadline.addingTimeInterval(60)
        session.updateDraft(invalid)

        let result = await session.save()

        XCTAssertEqual(result, .validationFailed)
        XCTAssertEqual(Set(session.validationErrors.keys), [.name, .tags, .paperDeadline])
        XCTAssertEqual(session.conferences, [original])
        let reloaded = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )
        XCTAssertEqual(reloaded.conferences, [original])
    }

    func testCancellingNewConferenceLeavesNoRecord() throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )

        XCTAssertEqual(session.requestNewConference(), .completed)
        var draft = try XCTUnwrap(session.draft)
        draft.name = "New Conference"
        session.updateDraft(draft)

        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.conferences, [original])

        session.discardChanges()

        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.selectedID, original.id)
        XCTAssertEqual(session.draft, original)
        let reloaded = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )
        XCTAssertEqual(reloaded.conferences, [original])
    }

    func testSavingNewConferenceCreatesUserConference() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let notifications = NoopConferenceNotificationSynchronizer()
        let session = try ConferenceEditingSession(
            store: store,
            notifications: notifications,
            makeID: { "custom2027" }
        )
        XCTAssertEqual(session.requestNewConference(), .completed)
        var draft = try XCTUnwrap(session.draft)
        draft.name = "Custom"
        session.updateDraft(draft)

        let result = await session.save()

        XCTAssertEqual(result, .saved)
        XCTAssertFalse(session.isDirty)
        let reloaded = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertEqual(Set(reloaded.conferences.map(\.id)), [original.id, "custom2027"])
    }

    func testDefaultConferenceCanBeHiddenAndRestored() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let notifications = NoopConferenceNotificationSynchronizer()
        let session = try ConferenceEditingSession(store: store, notifications: notifications)

        let deleteResult = await session.deleteSelectedConference()

        XCTAssertEqual(deleteResult, .saved)
        XCTAssertTrue(session.conferences.isEmpty)
        XCTAssertEqual(session.hiddenDefaultConferences, [original])
        let hiddenReload = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertTrue(hiddenReload.conferences.isEmpty)
        XCTAssertEqual(hiddenReload.hiddenDefaultConferences, [original])

        let restoreResult = await hiddenReload.restoreDefaultConference(id: original.id)

        XCTAssertEqual(restoreResult, .saved)
        XCTAssertEqual(hiddenReload.conferences, [original])
        XCTAssertTrue(hiddenReload.hiddenDefaultConferences.isEmpty)
        let restoredReload = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertEqual(restoredReload.conferences, [original])
    }

    func testAllHiddenDefaultConferencesCanBeRestoredTogether() async throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(
            defaults: [first, second],
            userData: ConferenceUserData(
                conferences: [],
                hiddenDefaultIDs: [first.id, second.id]
            )
        )
        let notifications = NoopConferenceNotificationSynchronizer()
        let session = try ConferenceEditingSession(store: store, notifications: notifications)

        let result = await session.restoreAllDefaultConferences()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(Set(session.conferences.map(\.id)), [first.id, second.id])
        XCTAssertTrue(session.hiddenDefaultConferences.isEmpty)
        let reloaded = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertEqual(Set(reloaded.conferences.map(\.id)), [first.id, second.id])
    }

    func testUserConferenceIsPermanentlyDeleted() async throws {
        let userConference = makeConference(id: "custom2027", name: "Custom")
        let store = InMemoryConferenceEditingStore(
            defaults: [],
            userData: ConferenceUserData(
                conferences: [userConference],
                hiddenDefaultIDs: []
            )
        )
        let notifications = NoopConferenceNotificationSynchronizer()
        let session = try ConferenceEditingSession(store: store, notifications: notifications)

        let result = await session.deleteSelectedConference()

        XCTAssertEqual(result, .saved)
        XCTAssertTrue(session.conferences.isEmpty)
        XCTAssertTrue(session.hiddenDefaultConferences.isEmpty)
        let reloaded = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertTrue(reloaded.conferences.isEmpty)
    }

    func testSwitchingConferenceWithDirtyDraftRequiresConfirmation() throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(defaults: [first, second])
        let session = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )
        let originalSelection = try XCTUnwrap(session.selectedID)
        let target = originalSelection == first.id ? second : first

        var edited = try XCTUnwrap(session.draft)
        edited.name += " Updated"
        session.updateDraft(edited)

        let result = session.requestSelection(id: target.id)

        XCTAssertEqual(result, .confirmationRequired)
        XCTAssertEqual(session.selectedID, originalSelection)
        XCTAssertEqual(session.draft, edited)

        session.discardChangesAndContinue()

        XCTAssertEqual(session.selectedID, target.id)
        XCTAssertEqual(session.draft, target)
    }

    func testSavingDirtyDraftThenSwitchingCommitsAndContinues() async throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(defaults: [first, second])
        let notifications = NoopConferenceNotificationSynchronizer()
        let session = try ConferenceEditingSession(store: store, notifications: notifications)
        let originalID = try XCTUnwrap(session.selectedID)
        let target = originalID == first.id ? second : first
        var edited = try XCTUnwrap(session.draft)
        edited.name += " Updated"
        session.updateDraft(edited)
        XCTAssertEqual(session.requestSelection(id: target.id), .confirmationRequired)

        let result = await session.saveChangesAndContinue()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(session.selectedID, target.id)
        let reloaded = try ConferenceEditingSession(store: store, notifications: notifications)
        XCTAssertEqual(reloaded.conferences.first { $0.id == edited.id }?.name, edited.name)
    }

    func testPersistenceFailureKeepsSavedConferenceUnchanged() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        store.saveError = NSError(
            domain: "ConferenceEditingSessionTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "磁盘空间不足"]
        )
        let session = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )
        var edited = try XCTUnwrap(session.draft)
        edited.name = "CVPR Updated"
        session.updateDraft(edited)

        let result = await session.save()

        XCTAssertEqual(result, .persistenceFailed("磁盘空间不足"))
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.conferences, [original])
        let reloaded = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )
        XCTAssertEqual(reloaded.conferences, [original])
    }

    func testNotificationFailureDoesNotRollBackSavedConference() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try ConferenceEditingSession(
            store: store,
            notifications: FailingConferenceNotificationSynchronizer()
        )
        var edited = try XCTUnwrap(session.draft)
        edited.name = "CVPR Updated"
        session.updateDraft(edited)

        let result = await session.save()

        XCTAssertEqual(result, .savedWithNotificationWarning("通知不可用"))
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.conferences.map(\.name), ["CVPR Updated"])
        let reloaded = try ConferenceEditingSession(
            store: store,
            notifications: NoopConferenceNotificationSynchronizer()
        )
        XCTAssertEqual(reloaded.conferences.map(\.name), ["CVPR Updated"])
    }

    func testNotificationWarningSurvivesSaveAndContinueNavigation() async throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(defaults: [first, second])
        let session = try ConferenceEditingSession(
            store: store,
            notifications: FailingConferenceNotificationSynchronizer()
        )
        let originalID = try XCTUnwrap(session.selectedID)
        let target = originalID == first.id ? second : first
        var edited = try XCTUnwrap(session.draft)
        edited.name += " Updated"
        session.updateDraft(edited)
        XCTAssertEqual(session.requestSelection(id: target.id), .confirmationRequired)

        let result = await session.saveChangesAndContinue()

        let warning = ConferenceEditingCommitResult.savedWithNotificationWarning("通知不可用")
        XCTAssertEqual(result, warning)
        XCTAssertEqual(session.selectedID, target.id)
        XCTAssertEqual(session.lastCommitResult, warning)
    }

    private func makeConference(id: String, name: String) -> Conference {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return Conference(
            id: id,
            name: name,
            year: 2027,
            category: "CV",
            abstractDeadline: now.addingTimeInterval(7 * 24 * 60 * 60),
            paperDeadline: now.addingTimeInterval(14 * 24 * 60 * 60),
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

private final class InMemoryConferenceEditingStore: ConferenceEditingStore {
    let defaults: [Conference]
    var userData: ConferenceUserData
    var saveError: Error?

    init(defaults: [Conference], userData: ConferenceUserData = .empty) {
        self.defaults = defaults
        self.userData = userData
    }

    func loadDefaultConferences() throws -> [Conference] {
        defaults
    }

    func loadUserData() throws -> ConferenceUserData {
        userData
    }

    func saveUserData(_ userData: ConferenceUserData) throws {
        if let saveError {
            throw saveError
        }
        self.userData = userData
    }
}

@MainActor
private struct NoopConferenceNotificationSynchronizer: ConferenceNotificationSynchronizing {
    func synchronize(conferences: [Conference]) async throws {}
}

@MainActor
private struct FailingConferenceNotificationSynchronizer: ConferenceNotificationSynchronizing {
    func synchronize(conferences: [Conference]) async throws {
        throw NSError(
            domain: "ConferenceEditingSessionTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "通知不可用"]
        )
    }
}

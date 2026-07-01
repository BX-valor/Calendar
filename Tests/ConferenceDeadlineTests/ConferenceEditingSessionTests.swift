import XCTest
@testable import ConferenceDeadline

@MainActor
final class ConferenceEditingSessionTests: XCTestCase {
    func testSessionReadsFromSharedCatalogSnapshot() throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let catalog = try ConferenceCatalog(
            persistence: store,
            refreshInterval: nil
        )
        let session = ConferenceEditingSession(catalog: catalog)
        var edited = original
        edited.name = "CVPR Updated"

        XCTAssertEqual(catalog.save(edited), .committed)

        XCTAssertEqual(session.conferences, [edited])
    }

    func testDraftChangesAreCommittedOnlyAfterSave() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try makeSession(store: store)

        var edited = try XCTUnwrap(session.draft)
        edited.name = "CVPR Updated"
        session.updateDraft(edited)

        XCTAssertEqual(session.conferences.map(\.name), ["CVPR"])
        let beforeSave = try makeSession(store: store)
        XCTAssertEqual(beforeSave.conferences.map(\.name), ["CVPR"])

        let result = await session.save()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(session.conferences.map(\.name), ["CVPR Updated"])
        let afterSave = try makeSession(store: store)
        XCTAssertEqual(afterSave.conferences.map(\.name), ["CVPR Updated"])
    }

    func testInvalidDraftCannotBeSaved() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try makeSession(store: store)

        var invalid = try XCTUnwrap(session.draft)
        invalid.name = "  "
        invalid.tags = ["推荐"]
        invalid.deadlineLifecycle[.abstract] = invalid.deadlineLifecycle[.paper]!
            .addingTimeInterval(60)
        session.updateDraft(invalid)

        let result = await session.save()

        XCTAssertEqual(result, .validationFailed)
        XCTAssertEqual(
            Set(session.validationErrors.keys),
            [.name, .tags, .deadline(.paper)]
        )
        XCTAssertEqual(session.conferences, [original])
        let reloaded = try makeSession(store: store)
        XCTAssertEqual(reloaded.conferences, [original])
    }

    func testCancellingNewConferenceLeavesNoRecord() throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try makeSession(store: store)

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
        let reloaded = try makeSession(store: store)
        XCTAssertEqual(reloaded.conferences, [original])
    }

    func testSavingNewConferenceCreatesUserConference() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try makeSession(
            store: store,
            makeID: { "custom2027" }
        )
        XCTAssertEqual(session.requestNewConference(), .completed)
        var draft = try XCTUnwrap(session.draft)
        draft.name = "Custom"
        session.updateDraft(draft)

        let result = await session.save()

        XCTAssertEqual(result, .saved)
        XCTAssertFalse(session.isDirty)
        let reloaded = try makeSession(store: store)
        XCTAssertEqual(Set(reloaded.conferences.map(\.id)), [original.id, "custom2027"])
    }

    func testDefaultConferenceCanBeHiddenAndRestored() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        let session = try makeSession(store: store)

        let deleteResult = await session.deleteSelectedConference()

        XCTAssertEqual(deleteResult, .saved)
        XCTAssertTrue(session.conferences.isEmpty)
        XCTAssertEqual(session.hiddenDefaultConferences, [original])
        let hiddenReload = try makeSession(store: store)
        XCTAssertTrue(hiddenReload.conferences.isEmpty)
        XCTAssertEqual(hiddenReload.hiddenDefaultConferences, [original])

        let restoreResult = await hiddenReload.restoreDefaultConference(id: original.id)

        XCTAssertEqual(restoreResult, .saved)
        XCTAssertEqual(hiddenReload.conferences, [original])
        XCTAssertTrue(hiddenReload.hiddenDefaultConferences.isEmpty)
        let restoredReload = try makeSession(store: store)
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
        let session = try makeSession(store: store)

        let result = await session.restoreAllDefaultConferences()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(Set(session.conferences.map(\.id)), [first.id, second.id])
        XCTAssertTrue(session.hiddenDefaultConferences.isEmpty)
        let reloaded = try makeSession(store: store)
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
        let session = try makeSession(store: store)

        let result = await session.deleteSelectedConference()

        XCTAssertEqual(result, .saved)
        XCTAssertTrue(session.conferences.isEmpty)
        XCTAssertTrue(session.hiddenDefaultConferences.isEmpty)
        let reloaded = try makeSession(store: store)
        XCTAssertTrue(reloaded.conferences.isEmpty)
    }

    func testSwitchingConferenceWithDirtyDraftRequiresConfirmation() throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(defaults: [first, second])
        let session = try makeSession(store: store)
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

    func testCancellingPendingNavigationKeepsDraftAndSelection() throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(defaults: [first, second])
        let session = try makeSession(store: store)
        let originalID = try XCTUnwrap(session.selectedID)
        let target = originalID == first.id ? second : first
        var edited = try XCTUnwrap(session.draft)
        edited.name += " Updated"
        session.updateDraft(edited)
        XCTAssertEqual(session.requestSelection(id: target.id), .confirmationRequired)

        session.cancelPendingNavigation()

        XCTAssertNil(session.pendingNavigation)
        XCTAssertEqual(session.selectedID, originalID)
        XCTAssertEqual(session.draft, edited)
        XCTAssertTrue(session.isDirty)
    }

    func testSavingDirtyDraftThenSwitchingCommitsAndContinues() async throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(defaults: [first, second])
        let session = try makeSession(store: store)
        let originalID = try XCTUnwrap(session.selectedID)
        let target = originalID == first.id ? second : first
        var edited = try XCTUnwrap(session.draft)
        edited.name += " Updated"
        session.updateDraft(edited)
        XCTAssertEqual(session.requestSelection(id: target.id), .confirmationRequired)

        let result = await session.saveChangesAndContinue()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(session.selectedID, target.id)
        let reloaded = try makeSession(store: store)
        XCTAssertEqual(reloaded.conferences.first { $0.id == edited.id }?.name, edited.name)
    }

    func testInvalidDraftCannotNavigateAfterSaveAndContinue() async throws {
        let first = makeConference(id: "cvpr2026", name: "CVPR")
        let second = makeConference(id: "icml2027", name: "ICML")
        let store = InMemoryConferenceEditingStore(defaults: [first, second])
        let session = try makeSession(store: store)
        let originalID = try XCTUnwrap(session.selectedID)
        let target = originalID == first.id ? second : first
        var invalid = try XCTUnwrap(session.draft)
        invalid.name = "  "
        session.updateDraft(invalid)
        XCTAssertEqual(session.requestSelection(id: target.id), .confirmationRequired)

        let result = await session.saveChangesAndContinue()

        XCTAssertEqual(result, .validationFailed)
        XCTAssertNil(session.pendingNavigation)
        XCTAssertEqual(session.selectedID, originalID)
        XCTAssertEqual(session.draft, invalid)
        XCTAssertEqual(session.validationErrors[.name], "会议名称不能为空")
        XCTAssertTrue(session.isDirty)
    }

    func testPersistenceFailureKeepsSavedConferenceUnchanged() async throws {
        let original = makeConference(id: "cvpr2026", name: "CVPR")
        let store = InMemoryConferenceEditingStore(defaults: [original])
        store.saveError = NSError(
            domain: "ConferenceEditingSessionTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "磁盘空间不足"]
        )
        let session = try makeSession(store: store)
        var edited = try XCTUnwrap(session.draft)
        edited.name = "CVPR Updated"
        session.updateDraft(edited)

        let result = await session.save()

        XCTAssertEqual(result, .persistenceFailed("磁盘空间不足"))
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.conferences, [original])
        let reloaded = try makeSession(store: store)
        XCTAssertEqual(reloaded.conferences, [original])
    }

    private func makeSession(
        store: InMemoryConferenceEditingStore,
        makeID: @escaping () -> String = { UUID().uuidString },
        now: @escaping () -> Date = Date.init
    ) throws -> ConferenceEditingSession {
        let catalog = try ConferenceCatalog(
            persistence: store,
            refreshInterval: nil
        )
        return ConferenceEditingSession(
            catalog: catalog,
            makeID: makeID,
            now: now
        )
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

private final class InMemoryConferenceEditingStore: ConferenceCatalogPersisting {
    let defaults: [Conference]
    var userData: ConferenceUserData
    var saveError: Error?
    private(set) var saveCount = 0

    init(defaults: [Conference], userData: ConferenceUserData = .empty) {
        self.defaults = defaults
        self.userData = userData
    }

    func load() throws -> ConferenceCatalogPersistenceState {
        ConferenceCatalogPersistenceState(
            defaults: defaults,
            userData: userData,
            recovery: nil,
            isWriteEnabled: true
        )
    }

    func save(_ userData: ConferenceUserData) throws {
        saveCount += 1
        if let saveError {
            throw saveError
        }
        self.userData = userData
    }
}

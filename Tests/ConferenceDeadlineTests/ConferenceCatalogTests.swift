import XCTest
@testable import ConferenceDeadline

@MainActor
final class ConferenceCatalogTests: XCTestCase {
    func testSnapshotOverlaysUsersAndExcludesHiddenDefaults() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 30)
        let hidden = makeConference(id: "icml2027", name: "ICML", deadlineOffset: 20)
        let override = makeConference(
            id: first.id,
            name: "CVPR Updated",
            deadlineOffset: 10
        )
        let user = makeConference(id: "custom2027", name: "Custom", deadlineOffset: 5)
        let persistence = InMemoryConferenceCatalogPersistence(
            defaults: [first, hidden],
            userData: ConferenceUserData(
                conferences: [override, user],
                hiddenDefaultIDs: [hidden.id]
            )
        )

        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )

        XCTAssertEqual(catalog.snapshot.conferences.map(\.id), [user.id, override.id])
        XCTAssertEqual(catalog.snapshot.conferences.first { $0.id == first.id }, override)
        XCTAssertEqual(catalog.snapshot.hiddenDefaultConferences, [hidden])
    }

    func testSavingConferenceCommitsPersistenceAndSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        let persistence = InMemoryConferenceCatalogPersistence(defaults: [original])
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )
        var edited = original
        edited.name = "CVPR Updated"

        let result = catalog.save(edited)

        XCTAssertEqual(result, .committed)
        XCTAssertEqual(persistence.userData.conferences, [edited])
        XCTAssertEqual(catalog.snapshot.conferences, [edited])
    }

    func testSavingBundledValueRemovesRedundantOverride() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        var override = original
        override.name = "CVPR Updated"
        let persistence = InMemoryConferenceCatalogPersistence(
            defaults: [original],
            userData: ConferenceUserData(
                conferences: [override],
                hiddenDefaultIDs: []
            )
        )
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )

        XCTAssertEqual(catalog.save(original), .committed)

        XCTAssertTrue(persistence.userData.conferences.isEmpty)
        XCTAssertEqual(catalog.snapshot.conferences, [original])
    }

    func testInvalidConferenceDoesNotMutatePersistenceOrSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        let persistence = InMemoryConferenceCatalogPersistence(defaults: [original])
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )
        let initialSnapshot = catalog.snapshot
        var invalid = original
        invalid.name = "  "
        invalid.year = 0
        invalid.tags = []
        invalid.deadlineLifecycle[.abstract] = invalid.deadlineLifecycle[.paper]!
            .addingTimeInterval(1)

        let result = catalog.save(invalid)

        XCTAssertEqual(
            result,
            .validationFailed([.name, .year, .tags, .deadline(.paper)])
        )
        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertEqual(catalog.snapshot, initialSnapshot)
    }

    func testPersistenceFailureLeavesSnapshotUnchanged() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        let persistence = InMemoryConferenceCatalogPersistence(defaults: [original])
        persistence.saveError = NSError(
            domain: "ConferenceCatalogTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "磁盘已满"]
        )
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )
        let initialSnapshot = catalog.snapshot
        var edited = original
        edited.name = "CVPR Updated"

        let result = catalog.save(edited)

        XCTAssertEqual(result, .persistenceFailed("磁盘已满"))
        XCTAssertEqual(persistence.userData, .empty)
        XCTAssertEqual(catalog.snapshot, initialSnapshot)
    }

    func testHidingAndRestoringDefaultConferencePreservesOverride() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        var override = original
        override.name = "CVPR Updated"
        let persistence = InMemoryConferenceCatalogPersistence(
            defaults: [original],
            userData: ConferenceUserData(conferences: [override], hiddenDefaultIDs: [])
        )
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )

        XCTAssertEqual(catalog.delete(id: original.id), .committed)
        XCTAssertTrue(catalog.snapshot.conferences.isEmpty)
        XCTAssertEqual(catalog.snapshot.hiddenDefaultConferences, [override])
        XCTAssertEqual(persistence.userData.conferences, [override])

        XCTAssertEqual(catalog.restoreDefault(id: original.id), .committed)
        XCTAssertEqual(catalog.snapshot.conferences, [override])
        XCTAssertTrue(catalog.snapshot.hiddenDefaultConferences.isEmpty)
    }

    func testDeletingUserConferenceRemovesItPermanently() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let user = makeConference(id: "custom2027", name: "Custom", deadlineOffset: 10)
        let persistence = InMemoryConferenceCatalogPersistence(
            defaults: [],
            userData: ConferenceUserData(conferences: [user], hiddenDefaultIDs: [])
        )
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )

        XCTAssertEqual(catalog.delete(id: user.id), .committed)
        XCTAssertEqual(persistence.userData, .empty)
        XCTAssertTrue(catalog.snapshot.conferences.isEmpty)
    }

    func testRestoringAllDefaultsPublishesEveryHiddenConference() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        let second = makeConference(id: "icml2027", name: "ICML", deadlineOffset: 20)
        let persistence = InMemoryConferenceCatalogPersistence(
            defaults: [first, second],
            userData: ConferenceUserData(
                conferences: [],
                hiddenDefaultIDs: [first.id, second.id]
            )
        )
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )

        XCTAssertEqual(catalog.restoreAllDefaults(), .committed)
        XCTAssertEqual(catalog.snapshot.conferences.map(\.id), [first.id, second.id])
        XCTAssertTrue(catalog.snapshot.hiddenDefaultConferences.isEmpty)
    }

    func testClockTickReordersCatalogAfterNextDeadlineChanges() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var first = makeConference(id: "first", name: "First", deadlineOffset: 10)
        first.deadlineLifecycle[.paper] = now.addingTimeInterval(100)
        let second = makeConference(id: "second", name: "Second", deadlineOffset: 20)
        let persistence = InMemoryConferenceCatalogPersistence(defaults: [first, second])
        let clock = ManualConferenceCatalogClock(now: now)
        let catalog = try ConferenceCatalog(persistence: persistence, clock: clock)

        XCTAssertEqual(catalog.snapshot.conferences.map(\.id), [first.id, second.id])

        clock.advance(to: now.addingTimeInterval(15))

        XCTAssertEqual(catalog.snapshot.conferences.map(\.id), [second.id, first.id])
    }

    func testBlockedRecoveryKeepsDefaultsReadableAndRejectsWrites() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        let persistence = InMemoryConferenceCatalogPersistence(
            defaults: [original],
            recovery: .writeBlocked("无法备份损坏文件"),
            isWriteEnabled: false
        )
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )
        var edited = original
        edited.name = "CVPR Updated"

        XCTAssertEqual(catalog.snapshot.conferences, [original])
        XCTAssertEqual(
            catalog.save(edited),
            .writeBlockedByRecovery("无法备份损坏文件")
        )
        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertEqual(catalog.snapshot.conferences, [original])
    }

    func testRecoveredCatalogNoticeCanBeDismissedWithoutBlockingWrites() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = makeConference(id: "cvpr2027", name: "CVPR", deadlineOffset: 10)
        let persistence = InMemoryConferenceCatalogPersistence(
            defaults: [original],
            recovery: .recovered(backupFileName: "userConferences.corrupt.json")
        )
        let catalog = try ConferenceCatalog(
            persistence: persistence,
            now: { now },
            refreshInterval: nil
        )

        catalog.dismissRecoveryNotice()

        XCTAssertNil(catalog.snapshot.recovery)
        XCTAssertTrue(catalog.snapshot.isWriteEnabled)
        XCTAssertEqual(catalog.save(original), .committed)
    }

    private func makeConference(
        id: String,
        name: String,
        deadlineOffset: TimeInterval
    ) -> Conference {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return Conference(
            id: id,
            name: name,
            year: 2027,
            category: "CV",
            abstractDeadline: now.addingTimeInterval(deadlineOffset),
            paperDeadline: now.addingTimeInterval(deadlineOffset + 1),
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

private final class InMemoryConferenceCatalogPersistence: ConferenceCatalogPersisting {
    let defaults: [Conference]
    var userData: ConferenceUserData
    var saveCount = 0
    var saveError: Error?
    let recovery: ConferenceCatalogRecovery?
    let isWriteEnabled: Bool

    init(
        defaults: [Conference],
        userData: ConferenceUserData = .empty,
        recovery: ConferenceCatalogRecovery? = nil,
        isWriteEnabled: Bool = true
    ) {
        self.defaults = defaults
        self.userData = userData
        self.recovery = recovery
        self.isWriteEnabled = isWriteEnabled
    }

    func load() throws -> ConferenceCatalogPersistenceState {
        ConferenceCatalogPersistenceState(
            defaults: defaults,
            userData: userData,
            recovery: recovery,
            isWriteEnabled: isWriteEnabled
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

@MainActor
private final class ManualConferenceCatalogClock: ConferenceCatalogClock {
    private(set) var now: Date
    private var onTick: (() -> Void)?

    init(now: Date) {
        self.now = now
    }

    func start(_ onTick: @escaping () -> Void) {
        self.onTick = onTick
    }

    func advance(to date: Date) {
        now = date
        onTick?()
    }
}

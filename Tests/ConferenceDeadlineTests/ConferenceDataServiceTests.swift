import XCTest
@testable import ConferenceDeadline

final class ConferenceDataServiceTests: XCTestCase {
    func testCorruptUserDataIsBackedUpBeforeCatalogRecovery() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaultsURL = directory.appendingPathComponent("conferences.json")
        let userDataURL = directory.appendingPathComponent("userConferences.json")
        let backupURL = directory.appendingPathComponent(
            "userConferences.corrupt-20260630-120000.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([makeConference()]).write(to: defaultsURL)
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: userDataURL)
        let dataService = ConferenceDataService(
            defaultConferencesURL: { defaultsURL },
            userConferencesURL: { userDataURL },
            recoveryTimestamp: { "20260630-120000" }
        )

        let state = try dataService.load()

        XCTAssertEqual(state.userData, .empty)
        XCTAssertEqual(
            state.recovery,
            .recovered(backupFileName: backupURL.lastPathComponent)
        )
        XCTAssertTrue(state.isWriteEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: userDataURL.path))
        XCTAssertEqual(try Data(contentsOf: backupURL), corruptData)
    }

    func testCatalogWritesAreBlockedWhenCorruptDataCannotBeBackedUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let defaultsURL = directory.appendingPathComponent("conferences.json")
        let userDataURL = directory.appendingPathComponent("userConferences.json")
        let backupURL = directory.appendingPathComponent(
            "userConferences.corrupt-20260630-120000.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([makeConference()]).write(to: defaultsURL)
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: userDataURL)
        try Data("existing-backup".utf8).write(to: backupURL)
        let dataService = ConferenceDataService(
            defaultConferencesURL: { defaultsURL },
            userConferencesURL: { userDataURL },
            recoveryTimestamp: { "20260630-120000" }
        )

        let state = try dataService.load()

        XCTAssertFalse(state.isWriteEnabled)
        guard case .writeBlocked(let message) = state.recovery else {
            return XCTFail("Expected write-blocked recovery")
        }
        XCTAssertTrue(message.contains("无法创建备份"))
        XCTAssertEqual(try Data(contentsOf: userDataURL), corruptData)
        XCTAssertEqual(try Data(contentsOf: backupURL), Data("existing-backup".utf8))
    }

    func testBundledConferencesDecodeThroughDeadlineLifecycle() throws {
        let dataService = ConferenceDataService(userConferencesURL: { nil })

        let conferences = try dataService.load().defaults

        XCTAssertFalse(conferences.isEmpty)
        XCTAssertTrue(
            conferences.allSatisfy { $0.deadlineLifecycle.entries.count >= 2 }
        )
    }

    func testLegacyUserConferenceArrayMigratesOnNextSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let userDataURL = directory.appendingPathComponent("userConferences.json")
        let defaultsURL = directory.appendingPathComponent("conferences.json")
        let conference = makeConference()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([Conference]()).write(to: defaultsURL)
        try encoder.encode([conference]).write(to: userDataURL)
        let dataService = ConferenceDataService(
            defaultConferencesURL: { defaultsURL },
            userConferencesURL: { userDataURL }
        )

        var userData = try dataService.load().userData

        XCTAssertEqual(userData.conferences, [conference])
        XCTAssertTrue(userData.hiddenDefaultIDs.isEmpty)

        userData.hiddenDefaultIDs.insert(conference.id)
        try dataService.save(userData)

        let savedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: userDataURL)) as? [String: Any]
        )
        XCTAssertNotNil(savedObject["conferences"])
        XCTAssertEqual(savedObject["hiddenDefaultIDs"] as? [String], [conference.id])
        XCTAssertEqual(try dataService.load().userData, userData)
    }

    private func makeConference() -> Conference {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return Conference(
            id: "cvpr2027",
            name: "CVPR",
            year: 2027,
            category: "CV",
            abstractDeadline: base,
            paperDeadline: base.addingTimeInterval(7 * 24 * 60 * 60),
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

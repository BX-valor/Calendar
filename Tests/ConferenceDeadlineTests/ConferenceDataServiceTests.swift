import XCTest
@testable import ConferenceDeadline

final class ConferenceDataServiceTests: XCTestCase {
    func testLegacyUserConferenceArrayMigratesOnNextSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let userDataURL = directory.appendingPathComponent("userConferences.json")
        let conference = makeConference()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([conference]).write(to: userDataURL)
        let dataService = ConferenceDataService(
            defaultConferencesURL: { nil },
            userConferencesURL: { userDataURL }
        )

        var userData = try dataService.loadUserData()

        XCTAssertEqual(userData.conferences, [conference])
        XCTAssertTrue(userData.hiddenDefaultIDs.isEmpty)

        userData.hiddenDefaultIDs.insert(conference.id)
        try dataService.saveUserData(userData)

        let savedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: userDataURL)) as? [String: Any]
        )
        XCTAssertNotNil(savedObject["conferences"])
        XCTAssertEqual(savedObject["hiddenDefaultIDs"] as? [String], [conference.id])
        XCTAssertEqual(try dataService.loadUserData(), userData)
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

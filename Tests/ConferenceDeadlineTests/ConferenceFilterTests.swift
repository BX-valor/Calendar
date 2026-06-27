import XCTest
@testable import ConferenceDeadline

final class ConferenceFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeConference(
        id: String,
        name: String = "Test",
        category: String? = nil,
        tags: [String] = ["CCF-A"]
    ) -> Conference {
        Conference(
            id: id,
            name: name,
            year: 2026,
            category: category,
            abstractDeadline: now.addingTimeInterval(7 * 24 * 60 * 60),
            paperDeadline: now.addingTimeInterval(14 * 24 * 60 * 60),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil,
            location: nil,
            venue: nil,
            website: nil,
            timezone: nil,
            tags: tags
        )
    }

    func testEmptyFilterIncludesAllConferences() {
        let conferences = [
            makeConference(id: "a", category: "CV", tags: ["CCF-A"]),
            makeConference(id: "b", category: "NLP", tags: ["CCF-B"]),
            makeConference(id: "c", category: nil, tags: ["CCF-C"])
        ]

        let filter = ConferenceFilter()

        XCTAssertEqual(conferences.filter { filter.includes($0) }.count, 3)
    }

    func testFilterBySingleTag() {
        let conferences = [
            makeConference(id: "a", tags: ["CCF-A"]),
            makeConference(id: "b", tags: ["CCF-B"]),
            makeConference(id: "c", tags: ["CCF-A", "CCF-B"])
        ]

        var filter = ConferenceFilter()
        filter.selectedTags = ["CCF-A"]

        let result = conferences.filter { filter.includes($0) }
        XCTAssertEqual(result.map(\.id), ["a", "c"])
    }

    func testFilterBySingleCategory() {
        let conferences = [
            makeConference(id: "a", category: "CV", tags: ["CCF-A"]),
            makeConference(id: "b", category: "NLP", tags: ["CCF-A"]),
            makeConference(id: "c", category: nil, tags: ["CCF-A"])
        ]

        var filter = ConferenceFilter()
        filter.selectedCategories = ["CV"]

        let result = conferences.filter { filter.includes($0) }
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func testFilterByTagAndCategory() {
        let conferences = [
            makeConference(id: "a", category: "CV", tags: ["CCF-A"]),
            makeConference(id: "b", category: "CV", tags: ["CCF-B"]),
            makeConference(id: "c", category: "NLP", tags: ["CCF-A"])
        ]

        var filter = ConferenceFilter()
        filter.selectedTags = ["CCF-A"]
        filter.selectedCategories = ["CV"]

        let result = conferences.filter { filter.includes($0) }
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func testNilCategoryDoesNotMatchAnyCategoryFilter() {
        let conference = makeConference(id: "a", category: nil, tags: ["CCF-A"])

        var filter = ConferenceFilter()
        filter.selectedCategories = ["CV", "NLP", "ML"]

        XCTAssertFalse(filter.includes(conference))
    }
}

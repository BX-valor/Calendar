import XCTest
@testable import ConferenceDeadline

final class DeadlineLifecycleTests: XCTestCase {
    func testEntriesFollowLifecycleOrderAndSkipMissingOptionalDates() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let lifecycle = DeadlineLifecycle(
            abstractDeadline: base,
            paperDeadline: base.addingTimeInterval(1),
            rebuttalDeadline: nil,
            finalDecisionDate: base.addingTimeInterval(3),
            conferenceDate: base.addingTimeInterval(4)
        )

        XCTAssertEqual(
            lifecycle.entries.map(\.kind),
            [.abstract, .paper, .finalDecision, .conference]
        )
    }

    func testSummaryUsesNextOrMostRecentDeadline() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let upcomingLifecycle = DeadlineLifecycle(
            abstractDeadline: now.addingTimeInterval(200),
            paperDeadline: now.addingTimeInterval(100),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil
        )
        let pastLifecycle = DeadlineLifecycle(
            abstractDeadline: now.addingTimeInterval(-200),
            paperDeadline: now.addingTimeInterval(-100),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil
        )

        XCTAssertEqual(
            upcomingLifecycle.summary(relativeTo: now),
            .upcoming(DeadlineEntry(kind: .paper, date: now.addingTimeInterval(100)))
        )
        XCTAssertEqual(
            pastLifecycle.summary(relativeTo: now),
            .past(DeadlineEntry(kind: .paper, date: now.addingTimeInterval(-100)))
        )
    }

    func testUrgencyUsesSevenAndThirtyDayBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 60 * 60

        XCTAssertEqual(
            DeadlineSummary.past(
                DeadlineEntry(kind: .paper, date: now.addingTimeInterval(-1))
            ).urgency(relativeTo: now),
            .past
        )
        XCTAssertEqual(
            DeadlineSummary.upcoming(
                DeadlineEntry(kind: .paper, date: now.addingTimeInterval(7 * day))
            ).urgency(relativeTo: now),
            .withinSevenDays
        )
        XCTAssertEqual(
            DeadlineSummary.upcoming(
                DeadlineEntry(kind: .paper, date: now.addingTimeInterval(30 * day))
            ).urgency(relativeTo: now),
            .withinThirtyDays
        )
        XCTAssertEqual(
            DeadlineSummary.upcoming(
                DeadlineEntry(kind: .paper, date: now.addingTimeInterval(30 * day + 1))
            ).urgency(relativeTo: now),
            .later
        )
    }

    func testDeadlineKindsExposeStableMetadata() {
        XCTAssertEqual(
            DeadlineKind.allCases.map(\.id),
            ["abstract", "paper", "rebuttal", "final-decision", "conference"]
        )
        XCTAssertEqual(
            DeadlineKind.allCases.map(\.displayName),
            ["摘要截止", "投稿截止", "Rebuttal", "Final Decision", "会议召开"]
        )
        XCTAssertEqual(
            DeadlineKind.allCases.map(\.isRequired),
            [true, true, false, false, false]
        )
    }

    func testDateCanBeEditedThroughDeadlineKind() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let updated = base.addingTimeInterval(2)
        var lifecycle = DeadlineLifecycle(
            abstractDeadline: base,
            paperDeadline: base.addingTimeInterval(1),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil
        )

        lifecycle[.paper] = updated
        XCTAssertEqual(lifecycle[.paper], updated)

        lifecycle[.rebuttal] = updated
        XCTAssertEqual(lifecycle[.rebuttal], updated)

        lifecycle[.rebuttal] = nil
        XCTAssertNil(lifecycle[.rebuttal])
    }

    func testValidationRejectsOnlyDatesThatReverseLifecycleOrder() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let valid = DeadlineLifecycle(
            abstractDeadline: base,
            paperDeadline: base,
            rebuttalDeadline: nil,
            finalDecisionDate: base.addingTimeInterval(2),
            conferenceDate: nil
        )
        let invalid = DeadlineLifecycle(
            abstractDeadline: base,
            paperDeadline: base.addingTimeInterval(3),
            rebuttalDeadline: nil,
            finalDecisionDate: base.addingTimeInterval(2),
            conferenceDate: base.addingTimeInterval(4)
        )

        XCTAssertTrue(valid.validationErrors.isEmpty)
        XCTAssertEqual(invalid.validationErrors, [.finalDecision: .beforePrevious])
    }

    func testConferenceRoundTripsLifecycleUsingFlatJSONKeys() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let conference = Conference(
            id: "cvpr2027",
            name: "CVPR",
            year: 2027,
            category: "CV",
            abstractDeadline: base,
            paperDeadline: base.addingTimeInterval(1),
            rebuttalDeadline: nil,
            finalDecisionDate: base.addingTimeInterval(3),
            conferenceDate: base.addingTimeInterval(4),
            location: nil,
            venue: nil,
            website: nil,
            timezone: "AoE",
            tags: ["CCF-A"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conference)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(
            conference.deadlineLifecycle.entries.map(\.kind),
            [.abstract, .paper, .finalDecision, .conference]
        )
        XCTAssertNotNil(object["abstractDeadline"])
        XCTAssertNotNil(object["paperDeadline"])
        XCTAssertNil(object["deadlineLifecycle"])
        XCTAssertEqual(try decoder.decode(Conference.self, from: data), conference)
    }
}

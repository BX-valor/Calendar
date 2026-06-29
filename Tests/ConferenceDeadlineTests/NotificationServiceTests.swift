import XCTest
import UserNotifications
@testable import ConferenceDeadline

final class NotificationServiceTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeConference(
        id: String = "cvpr2026",
        name: String = "CVPR",
        year: Int = 2026,
        abstractDeadline: Date? = nil,
        paperDeadline: Date? = nil,
        rebuttalDeadline: Date? = nil,
        finalDecisionDate: Date? = nil,
        conferenceDate: Date? = nil
    ) -> Conference {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return Conference(
            id: id,
            name: name,
            year: year,
            category: "CV",
            abstractDeadline: abstractDeadline ?? base.addingTimeInterval(7 * 24 * 60 * 60),
            paperDeadline: paperDeadline ?? base.addingTimeInterval(14 * 24 * 60 * 60),
            rebuttalDeadline: rebuttalDeadline,
            finalDecisionDate: finalDecisionDate,
            conferenceDate: conferenceDate,
            location: nil,
            venue: nil,
            website: nil,
            timezone: nil,
            tags: ["CCF-A"]
        )
    }

    func testTriggerDateIsOneDayBeforeAtNineAM() {
        // 2024-11-14 12:00:00 UTC
        let deadline = Date(timeIntervalSince1970: 1_731_600_000)
        let triggerDate = NotificationRequestBuilder.triggerDate(for: deadline, relativeTo: .distantPast)

        XCTAssertNotNil(triggerDate)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate!)

        // 前一天
        let expectedDay = calendar.date(byAdding: .day, value: -1, to: deadline)
        let expectedComponents = calendar.dateComponents([.year, .month, .day], from: expectedDay!)

        XCTAssertEqual(components.year, expectedComponents.year)
        XCTAssertEqual(components.month, expectedComponents.month)
        XCTAssertEqual(components.day, expectedComponents.day)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func testTriggerDateReturnsNilWhenInThePast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = Date(timeIntervalSince1970: 1_700_000_000)

        let triggerDate = NotificationRequestBuilder.triggerDate(for: deadline, relativeTo: now)
        XCTAssertNil(triggerDate)
    }

    func testRequestsIncludeAllExistingEvents() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let conference = makeConference(
            abstractDeadline: base.addingTimeInterval(7 * 24 * 60 * 60),
            paperDeadline: base.addingTimeInterval(14 * 24 * 60 * 60),
            rebuttalDeadline: base.addingTimeInterval(60 * 24 * 60 * 60),
            finalDecisionDate: base.addingTimeInterval(90 * 24 * 60 * 60),
            conferenceDate: base.addingTimeInterval(120 * 24 * 60 * 60)
        )

        let requests = NotificationRequestBuilder.requests(for: conference, relativeTo: base)

        XCTAssertEqual(requests.count, 5)
        let identifiers = Set(requests.map(\.identifier))
        XCTAssertEqual(identifiers, [
            "cvpr2026-abstract",
            "cvpr2026-paper",
            "cvpr2026-rebuttal",
            "cvpr2026-final-decision",
            "cvpr2026-conference"
        ])
    }

    func testNilEventsAreSkipped() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let conference = makeConference(
            abstractDeadline: base.addingTimeInterval(7 * 24 * 60 * 60),
            paperDeadline: base.addingTimeInterval(14 * 24 * 60 * 60),
            rebuttalDeadline: nil,
            finalDecisionDate: nil,
            conferenceDate: nil
        )

        let requests = NotificationRequestBuilder.requests(for: conference, relativeTo: base)

        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.trigger is UNCalendarNotificationTrigger })
    }

    func testPastEventsAreSkipped() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let conference = makeConference(
            abstractDeadline: now.addingTimeInterval(7 * 24 * 60 * 60),
            paperDeadline: now.addingTimeInterval(-7 * 24 * 60 * 60)
        )

        let requests = NotificationRequestBuilder.requests(for: conference, relativeTo: now)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.identifier, "cvpr2026-abstract")
    }

    func testNotificationContent() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let conference = makeConference(
            name: "NeurIPS",
            year: 2026,
            paperDeadline: base.addingTimeInterval(14 * 24 * 60 * 60)
        )

        let paperDeadline = try XCTUnwrap(
            conference.deadlineLifecycle.entries.first { $0.kind == .paper }
        )
        let request = NotificationRequestBuilder.request(
            for: conference,
            deadline: paperDeadline,
            relativeTo: base
        )

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.content.title, "AI 会议 Deadline 提醒")
        XCTAssertEqual(request?.content.body, "「NeurIPS 2026」投稿截止 将在 1 天后到来")
    }
}

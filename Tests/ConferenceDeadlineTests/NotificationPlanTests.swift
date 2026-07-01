import XCTest
@testable import ConferenceDeadline

final class NotificationPlanTests: XCTestCase {
    func testPlanContainsDomainNotificationForFutureDeadline() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12))
        )
        let abstractDeadline = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2027, month: 1, day: 8, hour: 23))
        )
        let conference = makeConference(abstractDeadline: abstractDeadline)

        let plan = NotificationPlan.make(
            conferences: [conference],
            relativeTo: now,
            calendar: calendar
        )

        let notification = try XCTUnwrap(
            plan.notifications.first { $0.id == "cvpr2027-abstract" }
        )
        XCTAssertEqual(notification.title, "AI 会议 Deadline 提醒")
        XCTAssertEqual(notification.body, "「CVPR 2027」摘要截止 将在 1 天后到来")
        let expectedTriggerDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2027,
                    month: 1,
                    day: 7,
                    hour: 9,
                    minute: 0
                )
            )
        )
        XCTAssertEqual(notification.triggerDate, expectedTriggerDate)
    }

    func testPlanIncludesEveryExistingDeadlineType() throws {
        let calendar = makeCalendar()
        let now = try makeDate(day: 1, hour: 12, calendar: calendar)
        let conference = makeConference(
            abstractDeadline: try makeDate(day: 8, hour: 23, calendar: calendar),
            paperDeadline: try makeDate(day: 9, hour: 23, calendar: calendar),
            rebuttalDeadline: try makeDate(day: 10, hour: 23, calendar: calendar),
            finalDecisionDate: try makeDate(day: 11, hour: 23, calendar: calendar),
            conferenceDate: try makeDate(day: 12, hour: 23, calendar: calendar)
        )

        let plan = NotificationPlan.make(
            conferences: [conference],
            relativeTo: now,
            calendar: calendar
        )

        XCTAssertEqual(Set(plan.notifications.map(\.id)), [
            "cvpr2027-abstract",
            "cvpr2027-paper",
            "cvpr2027-rebuttal",
            "cvpr2027-final-decision",
            "cvpr2027-conference"
        ])
    }

    func testPlanSkipsNotificationsWhoseTriggerTimeHasPassed() throws {
        let calendar = makeCalendar()
        let now = try makeDate(day: 7, hour: 12, calendar: calendar)
        let conference = makeConference(
            abstractDeadline: try makeDate(day: 8, hour: 23, calendar: calendar),
            paperDeadline: try makeDate(day: 9, hour: 23, calendar: calendar)
        )

        let plan = NotificationPlan.make(
            conferences: [conference],
            relativeTo: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.notifications.map(\.id), ["cvpr2027-paper"])
    }

    func testPlanIgnoresConferenceFactsThatDoNotAffectNotifications() throws {
        let calendar = makeCalendar()
        let now = try makeDate(day: 1, hour: 12, calendar: calendar)
        var conference = makeConference(
            abstractDeadline: try makeDate(day: 8, hour: 23, calendar: calendar)
        )
        let original = NotificationPlan.make(
            conferences: [conference],
            relativeTo: now,
            calendar: calendar
        )

        conference.category = "AI"
        conference.location = "Vancouver"
        conference.tags = ["CCF-A", "推荐"]
        let irrelevantEdit = NotificationPlan.make(
            conferences: [conference],
            relativeTo: now,
            calendar: calendar
        )

        XCTAssertEqual(irrelevantEdit, original)

        conference.name = "CVPR Updated"
        let relevantEdit = NotificationPlan.make(
            conferences: [conference],
            relativeTo: now,
            calendar: calendar
        )
        XCTAssertNotEqual(relevantEdit, original)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        day: Int,
        hour: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2027,
                    month: 1,
                    day: day,
                    hour: hour
                )
            )
        )
    }

    private func makeConference(
        abstractDeadline: Date,
        paperDeadline: Date? = nil,
        rebuttalDeadline: Date? = nil,
        finalDecisionDate: Date? = nil,
        conferenceDate: Date? = nil
    ) -> Conference {
        Conference(
            id: "cvpr2027",
            name: "CVPR",
            year: 2027,
            category: "CV",
            abstractDeadline: abstractDeadline,
            paperDeadline: paperDeadline ?? abstractDeadline.addingTimeInterval(24 * 60 * 60),
            rebuttalDeadline: rebuttalDeadline,
            finalDecisionDate: finalDecisionDate,
            conferenceDate: conferenceDate,
            location: nil,
            venue: nil,
            website: nil,
            timezone: "AoE",
            tags: ["CCF-A"]
        )
    }
}

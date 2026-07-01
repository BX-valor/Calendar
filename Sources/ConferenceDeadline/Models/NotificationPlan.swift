import Foundation

struct NotificationPlan: Equatable {
    let notifications: [DeadlineNotification]

    static func make(
        conferences: [Conference],
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> NotificationPlan {
        let notifications = conferences.flatMap { conference in
            conference.deadlineLifecycle.entries.compactMap { deadline in
                makeNotification(
                    conference: conference,
                    deadline: deadline,
                    relativeTo: now,
                    calendar: calendar
                )
            }
        }
        .sorted { $0.id < $1.id }

        return NotificationPlan(notifications: notifications)
    }

    private static func makeNotification(
        conference: Conference,
        deadline: DeadlineEntry,
        relativeTo now: Date,
        calendar: Calendar
    ) -> DeadlineNotification? {
        guard let dayBefore = calendar.date(
            byAdding: .day,
            value: -1,
            to: deadline.date
        ) else {
            return nil
        }

        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: dayBefore
        )
        components.hour = 9
        components.minute = 0
        guard let triggerDate = calendar.date(from: components),
              triggerDate > now else {
            return nil
        }

        return DeadlineNotification(
            id: "\(conference.id)-\(deadline.kind.id)",
            title: "AI 会议 Deadline 提醒",
            body: "「\(conference.name) \(conference.year)」\(deadline.kind.displayName) 将在 1 天后到来",
            triggerDate: triggerDate
        )
    }
}

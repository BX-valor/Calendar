import Foundation

struct Conference: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var year: Int
    var category: String?
    var abstractDeadline: Date
    var paperDeadline: Date
    var rebuttalDeadline: Date?
    var finalDecisionDate: Date?
    var conferenceDate: Date?
    var location: String?
    var venue: String?
    var website: String?
    var timezone: String?
    var tags: [String]

    enum DeadlineEvent: String, CaseIterable {
        case abstractDeadline = "摘要截止"
        case paperDeadline = "投稿截止"
        case rebuttalDeadline = "Rebuttal"
        case finalDecisionDate = "Final Decision"
        case conferenceDate = "会议召开"
    }

    /// Returns the next upcoming deadline relative to `now`.
    /// If all deadlines are in the past, returns the most recent past deadline.
    func nextDeadline(relativeTo now: Date = Date()) -> (event: DeadlineEvent, date: Date) {
        let candidates: [(DeadlineEvent, Date?)] = [
            (.abstractDeadline, abstractDeadline),
            (.paperDeadline, paperDeadline),
            (.rebuttalDeadline, rebuttalDeadline),
            (.finalDecisionDate, finalDecisionDate),
            (.conferenceDate, conferenceDate)
        ]

        let valid = candidates.compactMap { event, date -> (DeadlineEvent, Date)? in
            guard let date else { return nil }
            return (event, date)
        }

        let future = valid.filter { $0.1 >= now }.sorted { $0.1 < $1.1 }
        if let first = future.first {
            return first
        }

        // All deadlines passed: return the most recent one.
        return valid.sorted { $0.1 > $1.1 }.first ?? (.paperDeadline, paperDeadline)
    }

    /// Time interval from now to the next deadline. Negative if passed.
    func timeUntilNextDeadline(relativeTo now: Date = Date()) -> TimeInterval {
        nextDeadline(relativeTo: now).date.timeIntervalSince(now)
    }
}

extension Conference {
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return formatter
    }()

    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

import Foundation

enum DeadlineKind: String, CaseIterable, Identifiable {
    case abstract
    case paper
    case rebuttal
    case finalDecision = "final-decision"
    case conference

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .abstract: "摘要截止"
        case .paper: "投稿截止"
        case .rebuttal: "Rebuttal"
        case .finalDecision: "Final Decision"
        case .conference: "会议召开"
        }
    }

    var isRequired: Bool {
        switch self {
        case .abstract, .paper: true
        case .rebuttal, .finalDecision, .conference: false
        }
    }
}

struct DeadlineEntry: Equatable, Identifiable {
    let kind: DeadlineKind
    let date: Date

    var id: DeadlineKind { kind }
}

enum DeadlineSummary: Equatable {
    case upcoming(DeadlineEntry)
    case past(DeadlineEntry)

    var entry: DeadlineEntry {
        switch self {
        case .upcoming(let entry), .past(let entry):
            return entry
        }
    }

    func urgency(relativeTo now: Date) -> DeadlineUrgency {
        guard case .upcoming(let entry) = self else { return .past }
        let interval = entry.date.timeIntervalSince(now)
        guard interval >= 0 else { return .past }
        if interval <= 7 * 24 * 60 * 60 {
            return .withinSevenDays
        }
        if interval <= 30 * 24 * 60 * 60 {
            return .withinThirtyDays
        }
        return .later
    }
}

enum DeadlineUrgency: Equatable {
    case past
    case withinSevenDays
    case withinThirtyDays
    case later
}

enum DeadlineValidationError: Equatable {
    case beforePrevious
}

struct DeadlineLifecycle: Equatable {
    private var abstractDeadline: Date
    private var paperDeadline: Date
    private var rebuttalDeadline: Date?
    private var finalDecisionDate: Date?
    private var conferenceDate: Date?

    init(
        abstractDeadline: Date,
        paperDeadline: Date,
        rebuttalDeadline: Date?,
        finalDecisionDate: Date?,
        conferenceDate: Date?
    ) {
        self.abstractDeadline = abstractDeadline
        self.paperDeadline = paperDeadline
        self.rebuttalDeadline = rebuttalDeadline
        self.finalDecisionDate = finalDecisionDate
        self.conferenceDate = conferenceDate
    }

    subscript(kind: DeadlineKind) -> Date? {
        get {
            switch kind {
            case .abstract: abstractDeadline
            case .paper: paperDeadline
            case .rebuttal: rebuttalDeadline
            case .finalDecision: finalDecisionDate
            case .conference: conferenceDate
            }
        }
        set {
            switch kind {
            case .abstract:
                guard let newValue else { return }
                abstractDeadline = newValue
            case .paper:
                guard let newValue else { return }
                paperDeadline = newValue
            case .rebuttal:
                rebuttalDeadline = newValue
            case .finalDecision:
                finalDecisionDate = newValue
            case .conference:
                conferenceDate = newValue
            }
        }
    }

    var entries: [DeadlineEntry] {
        let dates: [(DeadlineKind, Date?)] = [
            (.abstract, abstractDeadline),
            (.paper, paperDeadline),
            (.rebuttal, rebuttalDeadline),
            (.finalDecision, finalDecisionDate),
            (.conference, conferenceDate)
        ]

        return dates.compactMap { kind, date in
            guard let date else { return nil }
            return DeadlineEntry(kind: kind, date: date)
        }
    }

    var validationErrors: [DeadlineKind: DeadlineValidationError] {
        var errors: [DeadlineKind: DeadlineValidationError] = [:]
        var previousDate: Date?

        for entry in entries {
            if let previousDate, entry.date < previousDate {
                errors[entry.kind] = .beforePrevious
            } else {
                previousDate = entry.date
            }
        }

        return errors
    }

    func summary(relativeTo now: Date) -> DeadlineSummary {
        if let next = entries
            .filter({ $0.date >= now })
            .min(by: { $0.date < $1.date }) {
            return .upcoming(next)
        }

        let mostRecent = entries.max(by: { $0.date < $1.date })!
        return .past(mostRecent)
    }
}

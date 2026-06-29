import Foundation

struct Conference: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var year: Int
    var category: String?
    var deadlineLifecycle: DeadlineLifecycle
    var location: String?
    var venue: String?
    var website: String?
    var timezone: String?
    var tags: [String]

    init(
        id: String,
        name: String,
        year: Int,
        category: String?,
        abstractDeadline: Date,
        paperDeadline: Date,
        rebuttalDeadline: Date?,
        finalDecisionDate: Date?,
        conferenceDate: Date?,
        location: String?,
        venue: String?,
        website: String?,
        timezone: String?,
        tags: [String]
    ) {
        self.id = id
        self.name = name
        self.year = year
        self.category = category
        deadlineLifecycle = DeadlineLifecycle(
            abstractDeadline: abstractDeadline,
            paperDeadline: paperDeadline,
            rebuttalDeadline: rebuttalDeadline,
            finalDecisionDate: finalDecisionDate,
            conferenceDate: conferenceDate
        )
        self.location = location
        self.venue = venue
        self.website = website
        self.timezone = timezone
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case year
        case category
        case abstractDeadline
        case paperDeadline
        case rebuttalDeadline
        case finalDecisionDate
        case conferenceDate
        case location
        case venue
        case website
        case timezone
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        year = try container.decode(Int.self, forKey: .year)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        deadlineLifecycle = DeadlineLifecycle(
            abstractDeadline: try container.decode(Date.self, forKey: .abstractDeadline),
            paperDeadline: try container.decode(Date.self, forKey: .paperDeadline),
            rebuttalDeadline: try container.decodeIfPresent(Date.self, forKey: .rebuttalDeadline),
            finalDecisionDate: try container.decodeIfPresent(Date.self, forKey: .finalDecisionDate),
            conferenceDate: try container.decodeIfPresent(Date.self, forKey: .conferenceDate)
        )
        location = try container.decodeIfPresent(String.self, forKey: .location)
        venue = try container.decodeIfPresent(String.self, forKey: .venue)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        tags = try container.decode([String].self, forKey: .tags)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(year, forKey: .year)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(deadlineLifecycle[.abstract]!, forKey: .abstractDeadline)
        try container.encode(deadlineLifecycle[.paper]!, forKey: .paperDeadline)
        try container.encodeIfPresent(deadlineLifecycle[.rebuttal], forKey: .rebuttalDeadline)
        try container.encodeIfPresent(deadlineLifecycle[.finalDecision], forKey: .finalDecisionDate)
        try container.encodeIfPresent(deadlineLifecycle[.conference], forKey: .conferenceDate)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(venue, forKey: .venue)
        try container.encodeIfPresent(website, forKey: .website)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        try container.encode(tags, forKey: .tags)
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

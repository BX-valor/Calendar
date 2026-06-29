import Foundation

struct ConferenceUserData: Codable, Equatable {
    var conferences: [Conference]
    var hiddenDefaultIDs: Set<String>

    static let empty = ConferenceUserData(conferences: [], hiddenDefaultIDs: [])

    private enum CodingKeys: String, CodingKey {
        case conferences
        case hiddenDefaultIDs
    }

    init(conferences: [Conference], hiddenDefaultIDs: Set<String>) {
        self.conferences = conferences
        self.hiddenDefaultIDs = hiddenDefaultIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conferences = try container.decodeIfPresent([Conference].self, forKey: .conferences) ?? []
        let hiddenIDs = try container.decodeIfPresent([String].self, forKey: .hiddenDefaultIDs) ?? []
        hiddenDefaultIDs = Set(hiddenIDs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conferences, forKey: .conferences)
        try container.encode(hiddenDefaultIDs.sorted(), forKey: .hiddenDefaultIDs)
    }

    func activeConferences(
        applyingTo defaults: [Conference],
        relativeTo now: Date = Date()
    ) -> [Conference] {
        var merged = defaults.filter { !hiddenDefaultIDs.contains($0.id) }

        for conference in conferences {
            guard !hiddenDefaultIDs.contains(conference.id) else { continue }
            if let index = merged.firstIndex(where: { $0.id == conference.id }) {
                merged[index] = conference
            } else {
                merged.append(conference)
            }
        }

        return merged.sorted {
            $0.deadlineLifecycle.summary(relativeTo: now).entry.date
                < $1.deadlineLifecycle.summary(relativeTo: now).entry.date
        }
    }
}

protocol ConferenceEditingStore: AnyObject {
    func loadDefaultConferences() throws -> [Conference]
    func loadUserData() throws -> ConferenceUserData
    func saveUserData(_ userData: ConferenceUserData) throws
}

@MainActor
protocol ConferenceNotificationSynchronizing {
    func synchronize(conferences: [Conference]) async throws
}

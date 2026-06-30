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

}

import Foundation

enum ConferenceDataError: Error, CustomStringConvertible {
    case resourceNotFound
    case decodeFailed(Error)

    var description: String {
        switch self {
        case .resourceNotFound:
            return "默认会议数据文件未找到。"
        case .decodeFailed(let error):
            return "解析会议数据失败：\(error.localizedDescription)"
        }
    }
}

final class ConferenceDataService: ConferenceEditingStore {
    static let shared = ConferenceDataService()

    private let defaultConferencesURL: () -> URL?
    private let userConferencesURL: () -> URL?

    init(
        defaultConferencesURL: @escaping () -> URL? = {
            Bundle.module.url(forResource: "conferences", withExtension: "json")
        },
        userConferencesURL: @escaping () -> URL? = ConferenceDataService.defaultUserConferencesURL
    ) {
        self.defaultConferencesURL = defaultConferencesURL
        self.userConferencesURL = userConferencesURL
    }

    /// Loads merged conferences: defaults overlaid by user-defined conferences.
    func loadAllConferences() throws -> [Conference] {
        let defaults = try loadDefaultConferences()
        let userData: ConferenceUserData
        do {
            userData = try loadUserData()
        } catch {
            print("用户会议数据损坏，忽略用户数据：\(error)")
            userData = .empty
        }
        return userData.activeConferences(applyingTo: defaults)
    }

    /// Loads built-in default conferences from the app bundle.
    func loadDefaultConferences() throws -> [Conference] {
        guard let url = defaultConferencesURL() else {
            throw ConferenceDataError.resourceNotFound
        }
        return try decodeConferences(from: url)
    }

    /// Loads user overrides and hidden Default Conference identifiers.
    /// Legacy files containing only a Conference array are migrated in memory.
    func loadUserData() throws -> ConferenceUserData {
        guard let url = userConferencesURL() else { return .empty }
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(ConferenceUserData.self, from: data)
        } catch {
            do {
                let conferences = try decoder.decode([Conference].self, from: data)
                return ConferenceUserData(conferences: conferences, hiddenDefaultIDs: [])
            } catch {
                throw ConferenceDataError.decodeFailed(error)
            }
        }
    }

    /// Saves user overrides and hidden Default Conference identifiers.
    func saveUserData(_ userData: ConferenceUserData) throws {
        guard let url = userConferencesURL() else {
            throw NSError(domain: "ConferenceDataService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取用户数据目录"])
        }

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(userData)
        try data.write(to: url, options: .atomic)
    }

    private func decodeConferences(from url: URL) throws -> [Conference] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Conference].self, from: data)
    }

    private static func defaultUserConferencesURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("ConferenceDeadline", isDirectory: true)
            .appendingPathComponent("userConferences.json")
    }
}

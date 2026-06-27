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

final class ConferenceDataService {
    static let shared = ConferenceDataService()

    private let userConferencesFilename = "userConferences.json"
    private let appSupportDirectoryName = "ConferenceDeadline"

    private init() {}

    /// Loads merged conferences: defaults overlaid by user-defined conferences.
    func loadAllConferences() throws -> [Conference] {
        let defaults = try loadDefaultConferences()
        let users = loadUserConferences() // never throws; returns empty on failure

        var merged = defaults
        for user in users {
            if let index = merged.firstIndex(where: { $0.id == user.id }) {
                merged[index] = user
            } else {
                merged.append(user)
            }
        }
        return merged.sorted { $0.timeUntilNextDeadline() < $1.timeUntilNextDeadline() }
    }

    /// Loads built-in default conferences from the app bundle.
    func loadDefaultConferences() throws -> [Conference] {
        guard let url = Bundle.module.url(forResource: "conferences", withExtension: "json") else {
            throw ConferenceDataError.resourceNotFound
        }
        return try decodeConferences(from: url)
    }

    /// Loads user-defined conferences from Application Support.
    /// Returns an empty array if the file is missing or corrupt.
    func loadUserConferences() -> [Conference] {
        guard let url = userConferencesURL() else { return [] }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try decodeConferences(from: url)
        } catch {
            print("用户会议数据损坏，忽略用户数据：\(error)")
            return []
        }
    }

    /// Saves user-defined conferences to Application Support.
    func saveUserConferences(_ conferences: [Conference]) throws {
        guard let url = userConferencesURL() else {
            throw NSError(domain: "ConferenceDataService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取用户数据目录"])
        }

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(conferences)
        try data.write(to: url, options: .atomic)
    }

    private func decodeConferences(from url: URL) throws -> [Conference] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Conference].self, from: data)
    }

    private func userConferencesURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(userConferencesFilename)
    }
}

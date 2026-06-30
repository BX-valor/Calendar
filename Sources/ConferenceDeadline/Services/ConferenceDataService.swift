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

final class ConferenceDataService: ConferenceCatalogPersisting {
    static let shared = ConferenceDataService()

    private let defaultConferencesURL: () -> URL?
    private let userConferencesURL: () -> URL?
    private let recoveryTimestamp: () -> String

    init(
        defaultConferencesURL: @escaping () -> URL? = {
            Bundle.module.url(forResource: "conferences", withExtension: "json")
        },
        userConferencesURL: @escaping () -> URL? = ConferenceDataService.defaultUserConferencesURL,
        recoveryTimestamp: @escaping () -> String = ConferenceDataService.defaultRecoveryTimestamp
    ) {
        self.defaultConferencesURL = defaultConferencesURL
        self.userConferencesURL = userConferencesURL
        self.recoveryTimestamp = recoveryTimestamp
    }

    func load() throws -> ConferenceCatalogPersistenceState {
        let defaults = try loadDefaultConferences()
        do {
            return ConferenceCatalogPersistenceState(
                defaults: defaults,
                userData: try loadUserData(),
                recovery: nil,
                isWriteEnabled: true
            )
        } catch {
            guard let userDataURL = userConferencesURL(),
                  FileManager.default.fileExists(atPath: userDataURL.path) else {
                throw error
            }

            let backupURL = recoveryBackupURL(for: userDataURL)
            do {
                try FileManager.default.moveItem(at: userDataURL, to: backupURL)
                return ConferenceCatalogPersistenceState(
                    defaults: defaults,
                    userData: .empty,
                    recovery: .recovered(backupFileName: backupURL.lastPathComponent),
                    isWriteEnabled: true
                )
            } catch {
                return ConferenceCatalogPersistenceState(
                    defaults: defaults,
                    userData: .empty,
                    recovery: .writeBlocked("用户数据损坏，且无法创建备份：\(error.localizedDescription)"),
                    isWriteEnabled: false
                )
            }
        }
    }

    func save(_ userData: ConferenceUserData) throws {
        try saveUserData(userData)
    }

    private func loadDefaultConferences() throws -> [Conference] {
        guard let url = defaultConferencesURL() else {
            throw ConferenceDataError.resourceNotFound
        }
        return try decodeConferences(from: url)
    }

    private func loadUserData() throws -> ConferenceUserData {
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

    private func saveUserData(_ userData: ConferenceUserData) throws {
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

    private func recoveryBackupURL(for userDataURL: URL) -> URL {
        let baseName = userDataURL.deletingPathExtension().lastPathComponent
        let fileExtension = userDataURL.pathExtension
        let backupName = "\(baseName).corrupt-\(recoveryTimestamp()).\(fileExtension)"
        return userDataURL.deletingLastPathComponent().appendingPathComponent(backupName)
    }

    private static func defaultRecoveryTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

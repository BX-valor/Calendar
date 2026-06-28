import Foundation
import Combine

@MainActor
final class ConferenceListViewModel: ObservableObject {
    @Published var conferences: [Conference] = []
    @Published var errorMessage: String?
    @Published var filter: ConferenceFilter = ConferenceFilter()
    @Published var notificationsEnabled: Bool

    private let preferences = NotificationPreferences.shared
    private var timer: AnyCancellable?

    /// 经过筛选并排序后的会议列表，视图应使用此属性渲染。
    var displayedConferences: [Conference] {
        conferences
            .filter { filter.includes($0) }
            .sorted { $0.timeUntilNextDeadline() < $1.timeUntilNextDeadline() }
    }

    init() {
        notificationsEnabled = preferences.isEnabled
        load()
        // Refresh the "time until deadline" calculations every minute.
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sortConferences()
            }
    }

    func load() {
        do {
            conferences = try ConferenceDataService.shared.loadAllConferences()
            errorMessage = nil
            rescheduleNotifications()
        } catch {
            conferences = []
            errorMessage = (error as? ConferenceDataError)?.description ?? error.localizedDescription
        }
    }

    func save() {
        do {
            // Only persist conferences that differ from defaults or are newly added.
            let defaults = (try? ConferenceDataService.shared.loadDefaultConferences()) ?? []
            let defaultsByID = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })

            let userConferences = conferences.filter { conference in
                guard let defaultConf = defaultsByID[conference.id] else { return true }
                return conference != defaultConf
            }

            try ConferenceDataService.shared.saveUserConferences(userConferences)
            errorMessage = nil
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func addConference(_ conference: Conference) {
        conferences.append(conference)
        sortConferences()
        save()
        rescheduleNotifications()
    }

    func updateConference(_ conference: Conference) {
        if let index = conferences.firstIndex(where: { $0.id == conference.id }) {
            conferences[index] = conference
            sortConferences()
            save()
            rescheduleNotifications()
        }
    }

    func deleteConference(_ conference: Conference) {
        conferences.removeAll { $0.id == conference.id }
        save()
        rescheduleNotifications()
    }

    func toggleNotifications(enabled: Bool) {
        preferences.isEnabled = enabled
        notificationsEnabled = enabled

        guard NotificationService.shared.isAvailable else {
            errorMessage = "通知功能需在完整 .app bundle 中运行，请使用 Xcode Archive 或 ./scripts/build_dmg.sh 打包后测试"
            if enabled {
                preferences.isEnabled = false
                notificationsEnabled = false
            }
            return
        }

        if enabled {
            NotificationService.shared.requestAuthorization { [weak self] granted in
                if granted {
                    self?.rescheduleNotifications()
                } else {
                    self?.preferences.isEnabled = false
                    self?.notificationsEnabled = false
                    self?.errorMessage = "需要系统通知权限才能开启提醒"
                }
            }
        } else {
            NotificationService.shared.removeAllNotifications()
        }
    }

    private func rescheduleNotifications() {
        guard preferences.isEnabled else { return }
        NotificationService.shared.scheduleNotifications(for: conferences)
    }

    func toggleTag(_ tag: String) {
        if filter.selectedTags.contains(tag) {
            filter.selectedTags.remove(tag)
        } else {
            filter.selectedTags.insert(tag)
        }
    }

    func toggleCategory(_ category: String) {
        if filter.selectedCategories.contains(category) {
            filter.selectedCategories.remove(category)
        } else {
            filter.selectedCategories.insert(category)
        }
    }

    func clearFilter() {
        filter = ConferenceFilter()
    }

    private func sortConferences() {
        conferences.sort { $0.timeUntilNextDeadline() < $1.timeUntilNextDeadline() }
    }
}

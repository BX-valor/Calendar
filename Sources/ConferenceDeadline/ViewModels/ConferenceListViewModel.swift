import Foundation
import Combine

@MainActor
final class ConferenceListViewModel: ObservableObject {
    @Published var conferences: [Conference] = []
    @Published var errorMessage: String?
    @Published var filter: ConferenceFilter = ConferenceFilter()
    @Published var notificationsEnabled: Bool
    @Published private(set) var editingSession: ConferenceEditingSession?

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

    func beginEditing() {
        guard editingSession == nil else { return }

        do {
            editingSession = try ConferenceEditingSession(
                store: ConferenceDataService.shared,
                notifications: LiveConferenceNotificationSynchronizer(),
                onConferencesChanged: { [weak self] conferences in
                    self?.conferences = conferences
                    self?.errorMessage = nil
                },
                onCommitCompleted: { [weak self] result in
                    if case .savedWithNotificationWarning(let message) = result {
                        self?.errorMessage = "会议已保存，但通知更新失败：\(message)"
                    }
                }
            )
            errorMessage = nil
        } catch {
            errorMessage = "无法开始编辑：\(error.localizedDescription)"
        }
    }

    func finishEditing() {
        editingSession = nil
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
        let conferences = conferences
        Task { [weak self] in
            do {
                try await LiveConferenceNotificationSynchronizer()
                    .synchronize(conferences: conferences)
            } catch {
                self?.errorMessage = "通知更新失败：\(error.localizedDescription)"
            }
        }
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

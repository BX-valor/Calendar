import Combine
import Foundation

@MainActor
final class ConferenceListViewModel: ObservableObject {
    @Published private(set) var snapshot: ConferenceCatalogSnapshot?
    @Published var errorMessage: String?
    @Published var filter = ConferenceFilter()
    @Published var notificationsEnabled: Bool
    @Published private(set) var editingSession: ConferenceEditingSession?

    var conferences: [Conference] {
        snapshot?.conferences ?? []
    }

    var displayedConferences: [Conference] {
        conferences.filter { filter.includes($0) }
    }

    var catalogRecovery: ConferenceCatalogRecovery? {
        snapshot?.recovery
    }

    var canEdit: Bool {
        snapshot?.isWriteEnabled == true
    }

    private let preferences = NotificationPreferences.shared
    private var catalog: ConferenceCatalog?
    private var catalogCancellable: AnyCancellable?

    init() {
        notificationsEnabled = preferences.isEnabled

        do {
            let catalog = try ConferenceCatalog(
                persistence: ConferenceDataService.shared
            )
            self.catalog = catalog
            snapshot = catalog.snapshot
            catalogCancellable = catalog.$snapshot
                .dropFirst()
                .sink { [weak self] snapshot in
                    self?.snapshot = snapshot
                }
            rescheduleNotifications()
        } catch {
            catalog = nil
            snapshot = nil
            errorMessage = (error as? ConferenceDataError)?.description
                ?? error.localizedDescription
        }
    }

    func beginEditing() {
        guard editingSession == nil, let catalog else { return }
        guard catalog.snapshot.isWriteEnabled else { return }

        editingSession = ConferenceEditingSession(
            catalog: catalog,
            notifications: LiveConferenceNotificationSynchronizer(),
            onCommitCompleted: { [weak self] result in
                if case .savedWithNotificationWarning(let message) = result {
                    self?.errorMessage = "会议已保存，但通知更新失败：\(message)"
                }
            }
        )
        errorMessage = nil
    }

    func finishEditing() {
        editingSession = nil
    }

    func dismissCatalogRecovery() {
        catalog?.dismissRecoveryNotice()
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
}

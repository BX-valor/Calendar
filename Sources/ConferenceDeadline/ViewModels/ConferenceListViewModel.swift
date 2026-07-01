import Combine
import Foundation

@MainActor
final class ConferenceListViewModel: ObservableObject {
    @Published private(set) var snapshot: ConferenceCatalogSnapshot?
    @Published var errorMessage: String?
    @Published var filter = ConferenceFilter()
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

    var notificationState: NotificationPolicyState {
        notificationPolicy?.state ?? .unavailable
    }

    var notificationsEnabled: Bool {
        notificationPolicy?.isEnabled == true
    }

    var canToggleNotifications: Bool {
        notificationState != .unavailable
    }

    private var catalog: ConferenceCatalog?
    private var notificationPolicy: NotificationPolicy?
    private var catalogCancellable: AnyCancellable?
    private var notificationPolicyCancellable: AnyCancellable?

    init() {
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
            let notificationPolicy = NotificationPolicy(catalog: catalog)
            self.notificationPolicy = notificationPolicy
            notificationPolicyCancellable = notificationPolicy.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
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
            catalog: catalog
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
        Task { [weak self] in
            await self?.notificationPolicy?.setEnabled(enabled)
        }
    }

    func retryNotificationSynchronization() {
        Task { [weak self] in
            await self?.notificationPolicy?.retry()
        }
    }

    func openNotificationSettings() {
        notificationPolicy?.openSystemSettings()
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
}

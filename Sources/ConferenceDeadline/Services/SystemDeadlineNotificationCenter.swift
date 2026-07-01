import AppKit
import Foundation
import UserNotifications

@MainActor
final class SystemDeadlineNotificationCenter: DeadlineNotificationCenterAdapting {
    private let center: UNUserNotificationCenter
    private let bundleIsAvailable: () -> Bool

    init(
        center: UNUserNotificationCenter = .current(),
        bundleIsAvailable: @escaping () -> Bool = {
            Bundle.main.bundleURL.pathExtension == "app"
        }
    ) {
        self.center = center
        self.bundleIsAvailable = bundleIsAvailable
    }

    var isAvailable: Bool { bundleIsAvailable() }

    func authorizationStatus() async -> NotificationPermission {
        guard isAvailable else { return .notDetermined }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> NotificationPermission {
        guard isAvailable else { return .notDetermined }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    var pendingIDs: Set<String> {
        get async {
            guard isAvailable else { return [] }
            return Set(await center.pendingNotificationRequests().map(\.identifier))
        }
    }

    func add(_ notification: DeadlineNotification) async throws {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notification.triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        try await center.add(
            UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: trigger
            )
        )
    }

    func removePending(withIDs ids: Set<String>) async {
        guard isAvailable, !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: Array(ids))
    }

    func removeAllPending() async {
        guard isAvailable else { return }
        center.removeAllPendingNotificationRequests()
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

import Foundation
import UserNotifications

/// 负责本地通知的授权、调度与取消。
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// 当前进程是否运行在完整的 .app bundle 中。
    /// SPM 直接运行的可执行文件没有 bundle identifier，调用 UNUserNotificationCenter 会崩溃。
    var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// 请求用户授权发送本地通知。
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isAvailable else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    /// 查询当前通知授权状态。
    func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        guard isAvailable else {
            DispatchQueue.main.async { completion(.notDetermined) }
            return
        }

        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    /// Replaces all pending notifications and reports scheduling failures.
    func synchronizeNotifications(for conferences: [Conference]) async throws {
        guard isAvailable else { return }

        removeAllNotifications()
        let requests = conferences.flatMap { NotificationRequestBuilder.requests(for: $0) }
        for request in requests {
            try await center.add(request)
        }
    }

    /// 移除所有已预约的本地通知。
    func removeAllNotifications() {
        guard isAvailable else { return }
        center.removeAllPendingNotificationRequests()
    }
}

@MainActor
struct LiveConferenceNotificationSynchronizer: ConferenceNotificationSynchronizing {
    private let preferences: NotificationPreferences

    init(preferences: NotificationPreferences = .shared) {
        self.preferences = preferences
    }

    func synchronize(conferences: [Conference]) async throws {
        guard preferences.isEnabled else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        try await NotificationService.shared.synchronizeNotifications(for: conferences)
    }
}

/// 将会议与 deadline 事件转换为 `UNNotificationRequest`。
enum NotificationRequestBuilder {
    /// 通知触发时间：deadline 前 1 天的上午 9:00。
    static let triggerHour = 9
    static let triggerMinute = 0

    /// 为某场会议生成所有待发送的通知请求。
    static func requests(
        for conference: Conference,
        relativeTo now: Date = Date()
    ) -> [UNNotificationRequest] {
        conference.deadlineLifecycle.entries.compactMap { deadline in
            request(for: conference, deadline: deadline, relativeTo: now)
        }
    }

    /// 为单个事件生成通知请求。如果触发时间已过，则返回 nil。
    static func request(
        for conference: Conference,
        deadline: DeadlineEntry,
        relativeTo now: Date = Date()
    ) -> UNNotificationRequest? {
        guard let triggerDate = triggerDate(for: deadline.date, relativeTo: now) else {
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = "AI 会议 Deadline 提醒"
        content.body = "「\(conference.name) \(conference.year)」\(deadline.kind.displayName) 将在 1 天后到来"
        content.sound = .default

        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let identifier = "\(conference.id)-\(deadline.kind.id)"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// 计算 deadline 前 1 天上午 9:00 的触发日期。
    /// 如果触发时间已经早于 `now`，返回 nil。
    static func triggerDate(for deadline: Date, relativeTo now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: deadline) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
        components.hour = triggerHour
        components.minute = triggerMinute

        guard let triggerDate = calendar.date(from: components), triggerDate > now else {
            return nil
        }
        return triggerDate
    }
}

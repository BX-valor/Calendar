import Foundation

/// 管理通知相关的用户偏好设置。
final class NotificationPreferences {
    static let shared = NotificationPreferences()

    private let key = "notificationsEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 是否已开启通知提醒。
    var isEnabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

import Foundation

struct DeadlineNotification: Equatable, Hashable {
    let id: String
    let title: String
    let body: String
    let triggerDate: Date
}

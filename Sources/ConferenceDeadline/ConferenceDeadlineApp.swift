import SwiftUI

@main
struct ConferenceDeadlineApp: App {
    @StateObject private var viewModel = ConferenceListViewModel()

    var body: some Scene {
        MenuBarExtra("ConferenceDeadline", systemImage: "calendar.badge.clock") {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

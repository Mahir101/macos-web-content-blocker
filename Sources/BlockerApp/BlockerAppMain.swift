import SwiftUI

@main
struct BlockerAppMain: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Content Blocker") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 560)
                .onAppear { model.startPolling() }
                .onDisappear { model.stopPolling() }
        }
        .windowResizability(.contentSize)
    }
}

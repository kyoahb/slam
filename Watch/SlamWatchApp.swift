import SwiftUI

@main
struct SlamWatchApp: App {
    @State private var model = WristModel(demo: ProcessInfo.processInfo.arguments.contains("-demo"))

    var body: some Scene {
        WindowGroup {
            WristView().environment(model)
        }
        .backgroundTask(.watchConnectivity) { await model.catchUp() }
    }
}

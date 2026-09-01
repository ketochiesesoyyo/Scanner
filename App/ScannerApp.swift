import SwiftUI
import Telemetry

@main
struct ScannerApp: App {
    @State private var session = ScanSessionModel()

    init() {
        #if DEBUG
        Telemetry.use(LogSink())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(session)
        }
    }
}

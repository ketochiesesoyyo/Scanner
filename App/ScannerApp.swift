import SwiftUI
import ScannerCore
import Telemetry

@main
struct ScannerApp: App {
    private enum Boot {
        case ready(Library, RecognitionQueue)
        case failed(String)
    }

    @State private var boot: Boot
    @State private var exporter = ExportService()

    init() {
        #if DEBUG
        Telemetry.use(LogSink())
        HangWatchdog.shared.start()
        #endif
        do {
            let library = try Library.live()
            let queue = RecognitionQueue(library: library)
            #if DEBUG
            DemoSeed.runIfRequested(library: library, queue: queue)
            #endif
            _boot = State(initialValue: .ready(library, queue))
        } catch {
            _boot = State(initialValue: .failed(error.localizedDescription))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch boot {
            case .ready(let library, let queue):
                HomeView()
                    .environment(library)
                    .environment(queue)
                    .environment(exporter)
                    .modifier(LockGate())
            case .failed(let message):
                ContentUnavailableView {
                    Label("Scanner can't open its library", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your scans are still on this iPhone. Restart the app; if this keeps happening, free up storage and try again.\n\n\(message)")
                }
            }
        }
    }
}

#if DEBUG
import Foundation

/// Debug-only main-thread watchdog: every 2 s it pings the main queue and prints a loud console line
/// if the ping isn't answered within 3 s. Turns "the app froze" into a timestamped fact in the Xcode
/// console, alongside the phase logs (ingest/OCR/push).
final class HangWatchdog: @unchecked Sendable {
    static let shared = HangWatchdog()
    private let queue = DispatchQueue(label: "mx.scanner.watchdog", qos: .userInitiated)
    private var started = false

    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            schedule()
        }
    }

    private func schedule() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            let semaphore = DispatchSemaphore(value: 0)
            let sentAt = Date()
            DispatchQueue.main.async { semaphore.signal() }
            if semaphore.wait(timeout: .now() + 3) == .timedOut {
                print("⚠️⚠️ WATCHDOG: main thread unresponsive for >3s (ping sent \(sentAt)). If this repeats, pause in Xcode and copy Thread 1's backtrace.")
                _ = semaphore.wait(timeout: .distantFuture) // wait out the hang, then resume pinging
                print("✅ WATCHDOG: main thread responsive again after \(String(format: "%.1f", Date().timeIntervalSince(sentAt)))s")
            }
            self?.schedule()
        }
    }
}
#endif

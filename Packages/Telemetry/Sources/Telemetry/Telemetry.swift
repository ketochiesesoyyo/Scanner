import Foundation
import os

public protocol TelemetrySink: Sendable {
    func record(_ event: TelemetryEvent)
}

/// Default: nothing is recorded anywhere.
public struct NoOpSink: TelemetrySink {
    public init() {}
    public func record(_ event: TelemetryEvent) {}
}

/// Debug builds: events go to the unified log so they can be checked in Console.app.
public struct LogSink: TelemetrySink {
    private let logger = Logger(subsystem: "mx.scanner.app", category: "telemetry")
    public init() {}
    public func record(_ event: TelemetryEvent) {
        logger.debug("\(event.name, privacy: .public) \(String(describing: event), privacy: .public)")
    }
}

public enum Telemetry {
    private static let sink = OSAllocatedUnfairLock<any TelemetrySink>(initialState: NoOpSink())

    public static func use(_ newSink: any TelemetrySink) {
        sink.withLock { $0 = newSink }
    }

    public static func record(_ event: TelemetryEvent) {
        sink.withLock { $0 }.record(event)
    }
}

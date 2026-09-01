// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Telemetry",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Telemetry", targets: ["Telemetry"])
    ],
    targets: [
        // PRD §12 event schema behind a protocol. MVP ships with no vendor; sinks are swappable at beta.
        .target(name: "Telemetry")
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CaptureKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "CaptureKit", targets: ["CaptureKit"])
    ],
    dependencies: [
        .package(path: "../ScannerCore")
    ],
    targets: [
        // Capture sources. M0: VisionKit stand-in + photo import. M3: AVFoundation + Vision live capture
        // with guidance and auto-capture (PRD CAP-01), which the stand-in cannot provide.
        .target(name: "CaptureKit", dependencies: ["ScannerCore"])
    ]
)

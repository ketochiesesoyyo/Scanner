// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Recognition",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "Recognition", targets: ["Recognition"])
    ],
    dependencies: [
        .package(path: "../ScannerCore")
    ],
    targets: [
        // On-device OCR today; quality scoring, duplicate detection and classification land here in M2.
        .target(name: "Recognition", dependencies: ["ScannerCore"])
    ]
)

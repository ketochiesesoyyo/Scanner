// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScannerCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ScannerCore", targets: ["ScannerCore"])
    ],
    targets: [
        // Domain model shared by every package: documents, pages, recognition results, export presets.
        .target(name: "ScannerCore")
    ]
)

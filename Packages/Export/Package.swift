// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Export",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "Export", targets: ["Export"])
    ],
    dependencies: [
        .package(path: "../ScannerCore"),
        .package(path: "../ImagePipeline"),
    ],
    targets: [
        // Standard, portable outputs (PRD EXP-01): PDF with an invisible text layer, later JPEG/TXT bundles.
        .target(name: "Export", dependencies: ["ScannerCore", "ImagePipeline"])
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImagePipeline",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "ImagePipeline", targets: ["ImagePipeline"])
    ],
    dependencies: [
        .package(path: "../ScannerCore")
    ],
    targets: [
        // Derivative rendering: downscale + encode today; perspective correction and filters in M3.
        .target(name: "ImagePipeline", dependencies: ["ScannerCore"])
    ]
)

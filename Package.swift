// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoogleTrends",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "GoogleTrends", targets: ["GoogleTrends"]),
        .library(name: "GoogleTrendsSource", targets: ["GoogleTrendsSource"])
    ],
    targets: [
        .binaryTarget(name: "GoogleTrends", path: ".build/distribution/GoogleTrends.xcframework"),
        .target(name: "GoogleTrendsSource", path: "Sources/GoogleTrends"),
        .testTarget(name: "GoogleTrendsTests", dependencies: ["GoogleTrendsSource"])
    ],
    swiftLanguageModes: [.v6]
)

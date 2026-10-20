// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrendingHashtag",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TrendingHashtag", targets: ["TrendingHashtag"]),
        .library(name: "TrendingHashtagSource", targets: ["TrendingHashtagSource"]),
        .library(name: "GoogleTrends", targets: ["GoogleTrends"]),
        .library(name: "GoogleTrendsSource", targets: ["GoogleTrendsSource"])
    ],
    targets: [
        .binaryTarget(name: "TrendingHashtag", path: ".build/distribution/TrendingHashtag.xcframework"),
        .target(name: "TrendingHashtagSource", path: "Sources/TrendingHashtag"),
        .target(name: "GoogleTrends", dependencies: ["TrendingHashtagSource"], path: "Sources/GoogleTrends"),
        .target(name: "GoogleTrendsSource", dependencies: ["TrendingHashtagSource"], path: "Sources/GoogleTrendsSource"),
        .testTarget(name: "TrendingHashtagTests", dependencies: ["TrendingHashtagSource", "GoogleTrends", "GoogleTrendsSource"])
    ],
    swiftLanguageModes: [.v6]
)

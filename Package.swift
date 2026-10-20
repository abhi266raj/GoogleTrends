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
        .binaryTarget(
            name: "TrendingHashtag",
            url: "https://github.com/abhi266raj/TrendingHashtag/releases/download/artifacts-0.2.0/TrendingHashtag.xcframework.zip",
            checksum: "43c2fdaedc2ef2024e5c21bf40c71e901dea2191d2016b427d7d4d76f77c803f"
        ),
        .target(name: "TrendingHashtagSource", path: "Sources/TrendingHashtag"),
        .target(name: "GoogleTrends", dependencies: ["TrendingHashtagSource"], path: "Sources/GoogleTrends"),
        .target(name: "GoogleTrendsSource", dependencies: ["TrendingHashtagSource"], path: "Sources/GoogleTrendsSource"),
        .testTarget(name: "TrendingHashtagTests", dependencies: ["TrendingHashtagSource", "GoogleTrends", "GoogleTrendsSource"])
    ],
    swiftLanguageModes: [.v6]
)

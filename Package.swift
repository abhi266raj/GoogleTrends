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
        .binaryTarget(
            name: "GoogleTrends",
            url: "https://github.com/abhi266raj/GoogleTrends/releases/download/artifacts-0.1.0/GoogleTrends.xcframework.zip",
            checksum: "af63b260f7a6485113b5e18288daf1167013759c7231a617aea96b032a908aea"
        ),
        .target(name: "GoogleTrendsSource", path: "Sources/GoogleTrends"),
        .testTarget(name: "GoogleTrendsTests", dependencies: ["GoogleTrendsSource"])
    ],
    swiftLanguageModes: [.v6]
)

# GoogleTrends

Independent Swift 6 package for Google Trends RSS search topics. Runs in your process, with no application server, Python, API keys, or package dependencies. macOS 13+, iOS 16+, Linux.

```swift
// Package.swift
.package(url: "https://github.com/abhi266raj/GoogleTrends.git", from: "0.1.0")
// Target dependencies: .product(name: "GoogleTrends", package: "GoogleTrends")
```

```swift
import GoogleTrends
let client = GoogleTrendsClient(region: "IN")
let topics = try await client.trendingTopics(limit: 15)
// topic.topic, topic.hashtag, topic.article?.title / url / source
```

Topics are Google trending searches, not social-network hashtag rankings. `hashtag` only formats a topic as a tag. The first usable associated news article is retained when available; topics without articles remain usable.

Internet required. Google's public RSS endpoint may change or rate-limit requests. Empty results, HTTP failures, malformed XML, and invalid limits (outside 1...100) surface as typed `GoogleTrendsError`; cancellation propagates. No cache or invented fallback topics. Inject `TrendsTransport` for tests or custom networking, and depend on `TrendsSearching` in application code.

For headline and keyword news search, use [NewsSearch](https://github.com/abhi266raj/NewsSearch), independently.

License: AGPL-3.0-only.

## Source and binary products

Following [AgentAtom](https://github.com/abhi266raj/AgentAtom), a single URL and version provide two independent products:

- `GoogleTrends`: prebuilt dynamic XCFramework; `import GoogleTrends`.
- `GoogleTrendsSource`: same implementation compiled from source; `import GoogleTrendsSource`.

Choose one product per dependency graph. The binary supports universal macOS, iPhone, and iOS Simulator. The source product also supports Linux. Development checkouts require `Scripts/build-xcframework.sh` before SwiftPM resolution. Published semantic tags download the verified binary automatically.

CI builds all three framework variants, runs fixture tests, tests both products as external consumers, and compiles a binary consumer for every shipped architecture. Only an increased `VERSION` merged into protected main publishes a release; unchanged versions validate only. Tags and assets are immutable. Main stays locked and publication only creates a generated manifest tag commit. See [RELEASING.md](RELEASING.md), [CONTRIBUTING.md](CONTRIBUTING.md) and [Distribution](Distribution/README.md).

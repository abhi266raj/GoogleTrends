# TrendingHashtag

Independent Swift 6 package for trending hashtags and topic discovery, supporting Google Trends as an option, configurable time windows (default 24 hours), 6-hour caching, language filtering (default English, Hindi, and Hinglish, disregarding other languages), and tag detail lookups (full title and short description) via external APIs. Runs in your process, with no application server, Python, API keys, or package dependencies. macOS 13+, iOS 16+, Linux.

```swift
// Package.swift
.package(url: "https://github.com/abhi266raj/TrendingHashtag.git", from: "0.2.0")
// Target dependencies: .product(name: "TrendingHashtag", package: "TrendingHashtag")
```

## Quick Start

```swift
import TrendingHashtag

// 1. Discover trending hashtags with default configuration
// (last 24 hours, cached for 6 hours, filtered for English/Hindi/Hinglish)
let client = TrendingHashtagClient(provider: .googleTrends(region: "IN"))
let hashtags = try await client.trendingHashtags(limit: 15)

for tag in hashtags {
    print(tag.hashtag)           // e.g. "#SamRaimi"
    print(tag.topic)             // e.g. "sam raimi"
    print(tag.title ?? "")       // Full headline title
    print(tag.shortDescription ?? "") // Short summary / description
}

// 2. Lookup full title and short description for a specific hashtag
let detail = try await client.tagDetail(for: "#SamRaimi")
print(detail.title)            // e.g. "Sam Raimi"
print(detail.shortDescription) // e.g. "American filmmaker and actor."
print(detail.source ?? "")     // "Wikipedia" or "Google Trends"
```

## Configuration

Customize time window, cache TTL, and language filtering:

```swift
let config = TrendingConfiguration(
    timeWindowHours: 24,       // Trends from last 24 hours (default: 24)
    cacheDuration: 6 * 3600,   // Cache duration in seconds (default: 6 hours)
    languages: [.english, .hindi, .hinglish], // Disregards other languages
    region: "IN"
)

let client = TrendingHashtagClient(
    provider: .googleTrends(),
    configuration: config
)
```

## Backward Compatibility with GoogleTrends

Existing integrations continue to work without code changes:

```swift
import GoogleTrends

let client = GoogleTrendsClient(region: "IN")
let topics = try await client.trendingTopics(limit: 15)
// topic.topic, topic.hashtag, topic.article?.title / url / source
```

## Features

- **Trending Hasthags with Google Trends Provider**: Clean `#Hashtag` format, news headlines, and metadata from Google Trends RSS.
- **Configurable Time Window**: Filter trends from the last N hours (default 24 hours).
- **Configurable Cache**: Actor-isolated in-memory cache defaulting to 6 hours (`cacheDuration: 6 * 3600`).
- **Language Filtering**: Detects and includes English, Hindi (Devanagari), and Hinglish (phonetic Roman Hindi). Disregards any topic in other languages (Arabic, Russian, Cyrillic, Chinese, Tamil, etc.).
- **Tag Detail Discovery**: Finds full title and short description via external API (`WikipediaTagDetailProvider`) with fallback to feed article snippets (`FeedTagDetailProvider`). Custom detail providers can be injected via `TagDetailSearching`.
- **Zero API Keys & Subprocesses**: Fully native Swift 6 async/await. Inject `TrendsTransport` for testing or custom networking.

License: AGPL-3.0-only.

## Source and Binary Products

Following [AgentAtom](https://github.com/abhi266raj/AgentAtom), a single URL and version provide independent products:

- `TrendingHashtag`: prebuilt dynamic XCFramework; `import TrendingHashtag`.
- `TrendingHashtagSource`: same implementation compiled from source; `import TrendingHashtagSource`.
- `GoogleTrends`: backward-compatible binary product alias; `import GoogleTrends`.
- `GoogleTrendsSource`: backward-compatible source product alias; `import GoogleTrendsSource`.

Choose one product per dependency graph. The binary supports universal macOS, iPhone, and iOS Simulator. The source product also supports Linux. Development checkouts require `Scripts/build-xcframework.sh` before SwiftPM resolution. Published semantic tags download the verified binary automatically.

CI builds all framework variants, runs deterministic tests, tests products as external consumers, and compiles binary consumers for every shipped architecture. Only an increased `VERSION` merged into protected main publishes a release; unchanged versions validate only. Tags and assets are immutable. See [RELEASING.md](RELEASING.md), [CONTRIBUTING.md](CONTRIBUTING.md) and [Distribution](Distribution/README.md).

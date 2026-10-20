// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Backward-compatible GoogleTrendsClient that delegates to TrendingHashtagClient with Google Trends provider option.
public struct GoogleTrendsClient: TrendsSearching {
    private let client: TrendingHashtagClient

    public init(
        transport: any TrendsTransport = URLSessionTrendsTransport(),
        region: String = "IN",
        configuration: TrendingConfiguration = .default
    ) {
        var config = configuration
        config.region = region
        self.client = TrendingHashtagClient(
            provider: .googleTrends(region: region),
            configuration: config,
            transport: transport
        )
    }

    /// Google Trends search topics, formatted as hashtags; these are not social-network rankings.
    public func trendingTopics(limit: Int = 15) async throws -> [TrendingTopic] {
        try await client.trendingTopics(limit: limit)
    }

    /// Trending hashtags with full details.
    public func trendingHashtags(limit: Int = 15) async throws -> [TrendingTopic] {
        try await client.trendingHashtags(limit: limit)
    }

    /// Lookup details for a tag or topic.
    public func tagDetail(for tagOrTopic: String) async throws -> TrendingHashtagDetail {
        try await client.tagDetail(for: tagOrTopic)
    }
}

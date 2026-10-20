// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public protocol TrendingPlatformProvider: Sendable {
    var platform: TrendingPlatform { get }
    func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingTopic]
}

/// Default platform provider using Google Trends RSS feed.
public struct GoogleTrendsPlatformProvider: TrendingPlatformProvider {
    public let platform: TrendingPlatform = .googleTrends
    public let region: String
    public let language: String

    public init(region: String = "IN", language: String = "en") {
        self.region = region
        self.language = language
    }

    public func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingTopic] {
        let effectiveRegion = region.isEmpty ? configuration.region : region
        var queryItems = [URLQueryItem(name: "geo", value: effectiveRegion)]
        if !language.isEmpty {
            queryItems.append(URLQueryItem(name: "hl", value: language))
        }

        guard var components = URLComponents(string: "https://trends.google.com/trending/rss") else {
            throw TrendingHashtagError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw TrendingHashtagError.invalidResponse }

        try Task.checkCancellation()
        let data = try await transport.data(from: url)
        try Task.checkCancellation()

        let items = try FeedParser.parse(data)

        // 1. Time window filter (default 24h)
        let filteredByTime: [FeedItem]
        if let hours = configuration.timeWindowHours, hours > 0 {
            let cutoff = Date().addingTimeInterval(-Double(hours * 3600))
            filteredByTime = items.filter { item in
                guard let published = item.publishedAt else { return true }
                return published >= cutoff
            }
        } else {
            filteredByTime = items
        }

        // 2. Language filter (English, Hindi, Hinglish default, disregard all other languages)
        let filteredByLanguage = filteredByTime.filter { item in
            LanguageFilter.isAllowed(
                topic: item.title,
                articleTitle: item.relatedArticle?.title,
                allowed: configuration.languages
            )
        }

        // 3. Deduplicate and construct topics
        var seen: Set<String> = []
        let topics = filteredByLanguage.compactMap { item -> TrendingTopic? in
            let lang = LanguageFilter.detectLanguage(text: item.title)
            let topic = TrendingTopic(
                topic: item.title,
                article: item.relatedArticle,
                title: item.relatedArticle?.title,
                shortDescription: item.relatedArticle?.snippet ?? (!item.description.isEmpty ? item.description : nil),
                language: lang,
                platform: .googleTrends,
                publishedAt: item.publishedAt
            )
            guard topic.hashtag.count > 1, seen.insert(topic.hashtag.lowercased()).inserted else { return nil }
            return topic
        }

        guard !topics.isEmpty else {
            throw TrendingHashtagError.noResults(["Google Trends: no topics matching configuration."])
        }

        return Array(topics.prefix(limit))
    }
}

/// Configurable Twitter / X trending hashtag provider.
public struct TwitterTrendsProvider: TrendingPlatformProvider {
    public let platform: TrendingPlatform = .twitter
    public let endpoint: URL?

    public init(endpoint: URL? = nil) {
        self.endpoint = endpoint
    }

    public func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingTopic] {
        guard let url = endpoint else {
            throw TrendingHashtagError.invalidInput("Twitter / X provider requires a configured endpoint URL.")
        }
        let data = try await transport.data(from: url)
        return try parsePlatformJSON(data: data, platform: .twitter, configuration: configuration, limit: limit)
    }
}

/// Configurable Instagram trending hashtag provider.
public struct InstagramTrendsProvider: TrendingPlatformProvider {
    public let platform: TrendingPlatform = .instagram
    public let endpoint: URL?

    public init(endpoint: URL? = nil) {
        self.endpoint = endpoint
    }

    public func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingTopic] {
        guard let url = endpoint else {
            throw TrendingHashtagError.invalidInput("Instagram provider requires a configured endpoint URL.")
        }
        let data = try await transport.data(from: url)
        return try parsePlatformJSON(data: data, platform: .instagram, configuration: configuration, limit: limit)
    }
}

/// Configurable YouTube trending hashtag / topics provider.
public struct YouTubeTrendsProvider: TrendingPlatformProvider {
    public let platform: TrendingPlatform = .youtube
    public let region: String
    public let endpoint: URL?

    public init(region: String = "IN", endpoint: URL? = nil) {
        self.region = region
        self.endpoint = endpoint
    }

    public func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingTopic] {
        let url = endpoint ?? URL(string: "https://www.youtube.com/feeds/videos.xml?chart=mostpopular&region=\(region)")!
        let data = try await transport.data(from: url)
        let items = (try? FeedParser.parse(data)) ?? []
        let topics = items.compactMap { item -> TrendingTopic? in
            let lang = LanguageFilter.detectLanguage(text: item.title)
            guard LanguageFilter.isAllowed(topic: item.title, allowed: configuration.languages) else { return nil }
            return TrendingTopic(
                topic: item.title,
                article: item.relatedArticle,
                title: item.relatedArticle?.title,
                shortDescription: item.relatedArticle?.snippet ?? item.description,
                language: lang,
                platform: .youtube,
                publishedAt: item.publishedAt
            )
        }
        guard !topics.isEmpty else {
            throw TrendingHashtagError.noResults(["YouTube: no trending topics matching configuration."])
        }
        return Array(topics.prefix(limit))
    }
}

/// Custom platform provider wrapper.
public struct CustomPlatformProvider: TrendingPlatformProvider {
    public let platform: TrendingPlatform
    private let fetcher: @Sendable (TrendingConfiguration, Int, any TrendsTransport) async throws -> [TrendingTopic]

    public init(
        platform: TrendingPlatform = .custom,
        fetcher: @escaping @Sendable (TrendingConfiguration, Int, any TrendsTransport) async throws -> [TrendingTopic]
    ) {
        self.platform = platform
        self.fetcher = fetcher
    }

    public func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingTopic] {
        try await fetcher(configuration, limit, transport)
    }
}

private func parsePlatformJSON(
    data: Data,
    platform: TrendingPlatform,
    configuration: TrendingConfiguration,
    limit: Int
) throws -> [TrendingTopic] {
    struct TagItem: Decodable {
        let tag: String?
        let name: String?
        let title: String?
        let description: String?
    }
    struct JSONPayload: Decodable {
        let hashtags: [TagItem]?
        let trends: [TagItem]?
        let items: [TagItem]?
    }

    let decoder = JSONDecoder()
    let payload = try decoder.decode(JSONPayload.self, from: data)
    let rawItems = payload.hashtags ?? payload.trends ?? payload.items ?? []

    let topics = rawItems.compactMap { item -> TrendingTopic? in
        let topicName = item.name ?? item.tag ?? item.title ?? ""
        guard !topicName.isEmpty else { return nil }
        let lang = LanguageFilter.detectLanguage(text: topicName)
        guard LanguageFilter.isAllowed(topic: topicName, articleTitle: item.description, allowed: configuration.languages) else { return nil }
        return TrendingTopic(
            topic: topicName,
            hashtag: item.tag,
            title: item.title,
            shortDescription: item.description,
            language: lang,
            platform: platform
        )
    }

    guard !topics.isEmpty else {
        throw TrendingHashtagError.noResults(["\(platform.displayName): no topics returned."])
    }
    return Array(topics.prefix(limit))
}

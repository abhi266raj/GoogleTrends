// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public protocol TrendingPlatformProvider: Sendable {
    var platform: TrendingPlatform { get }
    func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingHashtag]
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
    ) async throws -> [TrendingHashtag] {
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

        // 3. Deduplicate and construct hashtags
        var seen: Set<String> = []
        let hashtags = filteredByLanguage.compactMap { item -> TrendingHashtag? in
            let lang = LanguageFilter.detectLanguage(text: item.title)
            let hashtag = TrendingHashtag(
                topic: item.title,
                title: item.relatedArticle?.title,
                shortDescription: item.relatedArticle?.snippet ?? (!item.description.isEmpty ? item.description : nil),
                article: item.relatedArticle,
                language: lang,
                platform: .googleTrends,
                publishedAt: item.publishedAt
            )
            guard hashtag.hashtag.count > 1, seen.insert(hashtag.hashtag.lowercased()).inserted else { return nil }
            return hashtag
        }

        guard !hashtags.isEmpty else {
            throw TrendingHashtagError.noResults(["Google Trends: no topics matching configuration."])
        }

        return Array(hashtags.prefix(limit))
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
    ) async throws -> [TrendingHashtag] {
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
    ) async throws -> [TrendingHashtag] {
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
    ) async throws -> [TrendingHashtag] {
        let url = endpoint ?? URL(string: "https://www.youtube.com/feeds/videos.xml?chart=mostpopular&region=\(region)")!
        let data = try await transport.data(from: url)
        let items = (try? FeedParser.parse(data)) ?? []
        let hashtags = items.compactMap { item -> TrendingHashtag? in
            let lang = LanguageFilter.detectLanguage(text: item.title)
            guard LanguageFilter.isAllowed(topic: item.title, allowed: configuration.languages) else { return nil }
            return TrendingHashtag(
                topic: item.title,
                title: item.relatedArticle?.title,
                shortDescription: item.relatedArticle?.snippet ?? item.description,
                article: item.relatedArticle,
                language: lang,
                platform: .youtube,
                publishedAt: item.publishedAt
            )
        }
        guard !hashtags.isEmpty else {
            throw TrendingHashtagError.noResults(["YouTube: no trending topics matching configuration."])
        }
        return Array(hashtags.prefix(limit))
    }
}

/// Custom platform provider wrapper.
public struct CustomPlatformProvider: TrendingPlatformProvider {
    public let platform: TrendingPlatform
    private let fetcher: @Sendable (TrendingConfiguration, Int, any TrendsTransport) async throws -> [TrendingHashtag]

    public init(
        platform: TrendingPlatform = .custom,
        fetcher: @escaping @Sendable (TrendingConfiguration, Int, any TrendsTransport) async throws -> [TrendingHashtag]
    ) {
        self.platform = platform
        self.fetcher = fetcher
    }

    public func trendingHashtags(
        configuration: TrendingConfiguration,
        limit: Int,
        transport: any TrendsTransport
    ) async throws -> [TrendingHashtag] {
        try await fetcher(configuration, limit, transport)
    }
}

private func parsePlatformJSON(
    data: Data,
    platform: TrendingPlatform,
    configuration: TrendingConfiguration,
    limit: Int
) throws -> [TrendingHashtag] {
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

    let hashtags = rawItems.compactMap { item -> TrendingHashtag? in
        let topic = item.name ?? item.tag ?? item.title ?? ""
        guard !topic.isEmpty else { return nil }
        let lang = LanguageFilter.detectLanguage(text: topic)
        guard LanguageFilter.isAllowed(topic: topic, articleTitle: item.description, allowed: configuration.languages) else { return nil }
        return TrendingHashtag(
            hashtag: item.tag,
            topic: topic,
            title: item.title,
            shortDescription: item.description,
            language: lang,
            platform: platform
        )
    }

    guard !hashtags.isEmpty else {
        throw TrendingHashtagError.noResults(["\(platform.displayName): no topics returned."])
    }
    return Array(hashtags.prefix(limit))
}

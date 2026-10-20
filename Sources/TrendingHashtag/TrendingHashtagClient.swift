// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol TrendsTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionTrendsTransport: TrendsTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("TrendingHashtag/0.2 (+https://github.com/abhi266raj/TrendingHashtag)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml, application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TrendingHashtagError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw TrendingHashtagError.httpStatus(response.statusCode) }
        guard data.count <= 5_000_000 else { throw TrendingHashtagError.malformedFeed("Feed exceeds 5 MB.") }
        return data
    }
}

public protocol TrendsSearching: Sendable {
    func trendingTopics(limit: Int) async throws -> [TrendingTopic]
}

public protocol TrendingHashtagsSearching: TrendsSearching {
    func trendingHashtags(limit: Int) async throws -> [TrendingTopic]
    func tagDetail(for tagOrTopic: String) async throws -> TrendingHashtagDetail
}

public enum TrendingProviderOption: Sendable {
    case googleTrends(region: String = "IN", language: String = "en")
    case twitter(endpoint: URL? = nil)
    case instagram(endpoint: URL? = nil)
    case youtube(region: String = "IN", endpoint: URL? = nil)
    case custom(any TrendingPlatformProvider)

    public var provider: any TrendingPlatformProvider {
        switch self {
        case .googleTrends(let region, let language):
            return GoogleTrendsPlatformProvider(region: region, language: language)
        case .twitter(let endpoint):
            return TwitterTrendsProvider(endpoint: endpoint)
        case .instagram(let endpoint):
            return InstagramTrendsProvider(endpoint: endpoint)
        case .youtube(let region, let endpoint):
            return YouTubeTrendsProvider(region: region, endpoint: endpoint)
        case .custom(let customProvider):
            return customProvider
        }
    }
}

public struct TrendingHashtagClient: TrendingHashtagsSearching {
    public let providerOption: TrendingProviderOption
    public let platformProvider: any TrendingPlatformProvider
    public let configuration: TrendingConfiguration
    private let transport: any TrendsTransport
    private let cache: TrendingCache
    private let customDetailProvider: (any TagDetailSearching)?

    public init(
        provider: TrendingProviderOption = .googleTrends(),
        configuration: TrendingConfiguration = .default,
        transport: any TrendsTransport = URLSessionTrendsTransport(),
        cache: TrendingCache = TrendingCache(),
        detailProvider: (any TagDetailSearching)? = nil
    ) {
        self.providerOption = provider
        self.platformProvider = provider.provider
        self.configuration = configuration
        self.transport = transport
        self.cache = cache
        self.customDetailProvider = detailProvider
    }

    public init(
        platformProvider: any TrendingPlatformProvider,
        configuration: TrendingConfiguration = .default,
        transport: any TrendsTransport = URLSessionTrendsTransport(),
        cache: TrendingCache = TrendingCache(),
        detailProvider: (any TagDetailSearching)? = nil
    ) {
        self.providerOption = .custom(platformProvider)
        self.platformProvider = platformProvider
        self.configuration = configuration
        self.transport = transport
        self.cache = cache
        self.customDetailProvider = detailProvider
    }

    public func trendingHashtags(limit: Int = 15) async throws -> [TrendingTopic] {
        try await trendingHashtags(limit: limit, forceRefresh: false)
    }

    public func trendingHashtags(limit: Int = 15, forceRefresh: Bool = false) async throws -> [TrendingTopic] {
        try validate(limit: limit)

        let cacheKey = "\(platformProvider.platform.rawValue):\(configuration.region):\(configuration.timeWindowHours ?? 0):\(configuration.languages.map(\.rawValue).sorted().joined(separator: ","))"

        if !forceRefresh {
            if let cached = await cache.get(key: cacheKey, validFor: configuration.cacheDuration) {
                if !cached.isEmpty {
                    return Array(cached.prefix(limit))
                }
            }
        }

        let topics = try await platformProvider.trendingHashtags(
            configuration: configuration,
            limit: limit,
            transport: transport
        )

        guard !topics.isEmpty else {
            throw TrendingHashtagError.noResults(["\(platformProvider.platform.displayName): no topics matching configuration."])
        }

        await cache.set(key: cacheKey, topics: topics)
        return Array(topics.prefix(limit))
    }

    public func trendingTopics(limit: Int = 15) async throws -> [TrendingTopic] {
        try await trendingHashtags(limit: limit)
    }

    public func tagDetail(for tagOrTopic: String) async throws -> TrendingHashtagDetail {
        if let custom = customDetailProvider {
            return try await custom.detail(for: tagOrTopic)
        }

        // Default composite: Wikipedia summary API with feed extraction fallback
        let wiki = WikipediaTagDetailProvider(transport: transport)
        let feedFallback = FeedTagDetailProvider {
            try await self.trendingHashtags(limit: 100)
        }
        let composite = CompositeTagDetailProvider(primary: wiki, fallback: feedFallback)
        return try await composite.detail(for: tagOrTopic)
    }

    private func validate(limit: Int) throws {
        guard (1...100).contains(limit) else {
            throw TrendingHashtagError.invalidInput("News result limit must be between 1 and 100.")
        }
    }
}

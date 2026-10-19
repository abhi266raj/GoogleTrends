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
        request.setValue("GoogleTrends/0.1 (+https://github.com/abhi266raj/GoogleTrends)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GoogleTrendsError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw GoogleTrendsError.httpStatus(response.statusCode) }
        guard data.count <= 5_000_000 else { throw GoogleTrendsError.malformedFeed("Feed exceeds 5 MB.") }
        return data
    }
}

public protocol TrendsSearching: Sendable {
    func trendingTopics(limit: Int) async throws -> [TrendingTopic]
}

public struct GoogleTrendsClient: TrendsSearching {
    private let transport: any TrendsTransport
    private let region: String

    public init(transport: any TrendsTransport = URLSessionTrendsTransport(), region: String = "IN") {
        self.transport = transport
        self.region = region
    }

    /// Google Trends search topics, formatted as hashtags; these are not social-network rankings.
    public func trendingTopics(limit: Int = 15) async throws -> [TrendingTopic] {
        try validate(limit: limit)
        let feed = try url("https://trends.google.com/trending/rss", items: [.init(name: "geo", value: region)])
        try Task.checkCancellation()
        let data = try await transport.data(from: feed)
        try Task.checkCancellation()
        let items = try FeedParser.parse(data)
        var seen: Set<String> = []
        let topics = items.compactMap { item -> TrendingTopic? in
            let topic = TrendingTopic(topic: item.title, article: item.relatedArticle)
            guard topic.hashtag.count > 1, seen.insert(topic.hashtag.lowercased()).inserted else { return nil }
            return topic
        }
        guard !topics.isEmpty else { throw GoogleTrendsError.noResults(["Google Trends: no topics."]) }
        return Array(topics.prefix(limit))
    }

    private func validate(limit: Int) throws {
        guard (1...100).contains(limit) else { throw GoogleTrendsError.invalidInput("News result limit must be between 1 and 100.") }
    }

    private func url(_ base: String, items: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: base) else { throw GoogleTrendsError.invalidResponse }
        components.queryItems = items
        guard let url = components.url else { throw GoogleTrendsError.invalidResponse }
        return url
    }
}

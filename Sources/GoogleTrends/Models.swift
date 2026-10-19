import Foundation

public struct TrendArticle: Equatable, Sendable {
    public let title: String
    public let url: URL
    public let source: String
    public let publishedAt: Date?

    public init(title: String, url: URL, source: String, publishedAt: Date? = nil) {
        self.title = title
        self.url = url
        self.source = source
        self.publishedAt = publishedAt
    }
}

public struct TrendingTopic: Equatable, Sendable {
    public let topic: String
    public let article: TrendArticle?
    public var hashtag: String {
        "#" + topic.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    public init(topic: String, article: TrendArticle? = nil) {
        self.topic = topic
        self.article = article
    }
}

public enum GoogleTrendsError: Error, LocalizedError, Sendable {
    case invalidInput(String)
    case invalidResponse
    case httpStatus(Int)
    case malformedFeed(String)
    case noResults([String])

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .invalidResponse: "News source returned an invalid response."
        case .httpStatus(let code): "News source returned HTTP \(code)."
        case .malformedFeed(let detail): "Could not parse news feed: \(detail)"
        case .noResults(let attempts): "No news results. " + attempts.joined(separator: " ")
        }
    }
}

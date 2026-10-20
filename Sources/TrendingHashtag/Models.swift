// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public enum TrendingPlatform: String, Sendable, CaseIterable, Hashable, Codable {
    case googleTrends = "google_trends"
    case twitter = "twitter"
    case instagram = "instagram"
    case youtube = "youtube"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .googleTrends: return "Google Trends"
        case .twitter: return "Twitter / X"
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        case .custom: return "Custom"
        }
    }
}

public enum TrendingLanguage: String, Sendable, CaseIterable, Hashable, Codable {
    case english = "en"
    case hindi = "hi"
    case hinglish = "hinglish"
    case other = "other"
}

public struct TrendingConfiguration: Sendable, Equatable {
    /// How many hours of trends to include. Default is 24 hours. Nil or <=0 disables filtering by publication age.
    public var timeWindowHours: Int?
    /// How long to cache trending results in seconds. Default is 6 hours (21,600 seconds).
    public var cacheDuration: TimeInterval
    /// Allowed languages for trending topics. Topics in any other language are disregarded.
    /// Default includes English, Hindi, and Hinglish.
    public var languages: Set<TrendingLanguage>
    /// Region code (default "IN").
    public var region: String
    /// Default platform to query (default: Google Trends).
    public var platform: TrendingPlatform

    public init(
        timeWindowHours: Int? = 24,
        cacheDuration: TimeInterval = 6 * 3600,
        languages: Set<TrendingLanguage> = [.english, .hindi, .hinglish],
        region: String = "IN",
        platform: TrendingPlatform = .googleTrends
    ) {
        self.timeWindowHours = timeWindowHours
        self.cacheDuration = cacheDuration
        self.languages = languages
        self.region = region
        self.platform = platform
    }

    public static let `default` = TrendingConfiguration()
}

public struct TrendArticle: Equatable, Sendable {
    public let title: String
    public let url: URL
    public let source: String
    public let publishedAt: Date?
    public let snippet: String?

    public init(title: String, url: URL, source: String, publishedAt: Date? = nil, snippet: String? = nil) {
        self.title = title
        self.url = url
        self.source = source
        self.publishedAt = publishedAt
        self.snippet = snippet
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

public struct TrendingHashtag: Equatable, Sendable, Identifiable {
    public var id: String { hashtag }
    public let hashtag: String
    public let topic: String
    public let title: String?
    public let shortDescription: String?
    public let article: TrendArticle?
    public let language: TrendingLanguage
    public let platform: TrendingPlatform
    public let publishedAt: Date?

    public init(
        hashtag: String? = nil,
        topic: String,
        title: String? = nil,
        shortDescription: String? = nil,
        article: TrendArticle? = nil,
        language: TrendingLanguage = .english,
        platform: TrendingPlatform = .googleTrends,
        publishedAt: Date? = nil
    ) {
        self.topic = topic
        self.hashtag = hashtag ?? ("#" + topic.components(separatedBy: CharacterSet.alphanumerics.inverted).joined())
        self.title = title ?? article?.title
        self.shortDescription = shortDescription ?? article?.snippet
        self.article = article
        self.language = language
        self.platform = platform
        self.publishedAt = publishedAt ?? article?.publishedAt
    }
}

public struct TrendingHashtagDetail: Equatable, Sendable {
    public let tag: String
    public let title: String
    public let shortDescription: String
    public let source: String?
    public let url: URL?
    public let publishedAt: Date?

    public init(
        tag: String,
        title: String,
        shortDescription: String,
        source: String? = nil,
        url: URL? = nil,
        publishedAt: Date? = nil
    ) {
        self.tag = tag.hasPrefix("#") ? tag : "#" + tag
        self.title = title
        self.shortDescription = shortDescription
        self.source = source
        self.url = url
        self.publishedAt = publishedAt
    }
}

public enum TrendingHashtagError: Error, LocalizedError, Sendable, Equatable {
    case invalidInput(String)
    case invalidResponse
    case httpStatus(Int)
    case malformedFeed(String)
    case noResults([String])
    case detailNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .invalidResponse: "News source returned an invalid response."
        case .httpStatus(let code): "News source returned HTTP \(code)."
        case .malformedFeed(let detail): "Could not parse feed: \(detail)"
        case .noResults(let attempts): "No results. " + attempts.joined(separator: " ")
        case .detailNotFound(let tag): "No detail available for hashtag: \(tag)"
        }
    }
}

public typealias GoogleTrendsError = TrendingHashtagError

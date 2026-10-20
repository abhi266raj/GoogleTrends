// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public protocol TagDetailSearching: Sendable {
    func detail(for tagOrTopic: String) async throws -> TrendingHashtagDetail
}

/// Fetches topic details from the Wikipedia REST Summary API.
public struct WikipediaTagDetailProvider: TagDetailSearching {
    private let transport: any TrendsTransport
    private let language: String

    public init(transport: any TrendsTransport = URLSessionTrendsTransport(), language: String = "en") {
        self.transport = transport
        self.language = language
    }

    public func detail(for tagOrTopic: String) async throws -> TrendingHashtagDetail {
        let cleanTopic = clean(tagOrTopic)
        guard !cleanTopic.isEmpty else {
            throw TrendingHashtagError.invalidInput("Topic or tag must not be empty.")
        }

        let detected = LanguageFilter.detectLanguage(text: cleanTopic)
        let langCode = (detected == .hindi) ? "hi" : language

        guard let encoded = cleanTopic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://\(langCode).wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            throw TrendingHashtagError.invalidInput("Could not form detail URL for topic: \(cleanTopic)")
        }

        let data: Data
        do {
            data = try await transport.data(from: url)
        } catch {
            throw TrendingHashtagError.detailNotFound(tagOrTopic)
        }

        let decoder = JSONDecoder()
        guard let summary = try? decoder.decode(WikipediaSummaryResponse.self, from: data) else {
            throw TrendingHashtagError.detailNotFound(tagOrTopic)
        }

        let title = summary.title ?? cleanTopic
        let description = summary.extract ?? summary.description ?? ""
        guard !description.isEmpty else {
            throw TrendingHashtagError.detailNotFound(tagOrTopic)
        }

        let pageURL: URL? = summary.contentUrls?.desktop?.page.flatMap(URL.init(string:))

        return TrendingHashtagDetail(
            tag: "#" + cleanTopic.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(),
            title: title,
            shortDescription: description,
            source: "Wikipedia",
            url: pageURL,
            publishedAt: nil
        )
    }

    private func clean(_ tagOrTopic: String) -> String {
        var cleaned = tagOrTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        return cleaned
    }

    private struct WikipediaSummaryResponse: Decodable {
        let title: String?
        let description: String?
        let extract: String?
        let contentUrls: ContentUrls?

        enum CodingKeys: String, CodingKey {
            case title
            case description
            case extract
            case contentUrls = "content_urls"
        }

        struct ContentUrls: Decodable {
            let desktop: PageUrl?
            struct PageUrl: Decodable {
                let page: String?
            }
        }
    }
}

/// Extracts tag detail from existing hashtag/article data.
public struct FeedTagDetailProvider: TagDetailSearching {
    private let fallbackTopics: @Sendable () async throws -> [TrendingHashtag]

    public init(fallbackTopics: @escaping @Sendable () async throws -> [TrendingHashtag]) {
        self.fallbackTopics = fallbackTopics
    }

    public func detail(for tagOrTopic: String) async throws -> TrendingHashtagDetail {
        let normalized = tagOrTopic.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTag = normalized.hasPrefix("#") ? normalized : "#" + normalized
        let normalizedTopic = normalized.hasPrefix("#") ? String(normalized.dropFirst()) : normalized

        let topics = try await fallbackTopics()
        if let match = topics.first(where: {
            $0.hashtag.lowercased() == normalizedTag || $0.topic.lowercased() == normalizedTopic
        }) {
            let title = match.title ?? match.topic
            let desc = match.shortDescription ?? match.article?.snippet ?? match.title ?? match.topic
            return TrendingHashtagDetail(
                tag: match.hashtag,
                title: title,
                shortDescription: desc,
                source: match.article?.source ?? "Google Trends",
                url: match.article?.url,
                publishedAt: match.publishedAt
            )
        }
        throw TrendingHashtagError.detailNotFound(tagOrTopic)
    }
}

/// Tries external API first, falling back to feed-extracted detail.
public struct CompositeTagDetailProvider: TagDetailSearching {
    private let primary: any TagDetailSearching
    private let fallback: any TagDetailSearching

    public init(primary: any TagDetailSearching, fallback: any TagDetailSearching) {
        self.primary = primary
        self.fallback = fallback
    }

    public func detail(for tagOrTopic: String) async throws -> TrendingHashtagDetail {
        do {
            return try await primary.detail(for: tagOrTopic)
        } catch {
            return try await fallback.detail(for: tagOrTopic)
        }
    }
}

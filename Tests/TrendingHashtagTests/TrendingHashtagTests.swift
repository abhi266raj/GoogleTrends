// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Testing
import TrendingHashtagSource
import GoogleTrendsSource

private actor CountingFixtureTransport: TrendsTransport {
    private let responses: [Result<Data, TrendingHashtagError>]
    private var index = 0
    private(set) var callCount = 0

    init(responses: [Result<Data, TrendingHashtagError>]) {
        self.responses = responses
    }

    func data(from url: URL) async throws -> Data {
        callCount += 1
        let res = responses[min(index, responses.count - 1)]
        index += 1
        return try res.get()
    }
}

private actor CustomHandlerTransport: TrendsTransport {
    private let handler: @Sendable (URL) async throws -> Data
    private(set) var callCount = 0

    init(_ handler: @escaping @Sendable (URL) async throws -> Data) {
        self.handler = handler
    }

    func data(from url: URL) async throws -> Data {
        callCount += 1
        return try await handler(url)
    }
}

@Test func parsesTrendArticleWithoutOverwritingTopic() async throws {
    let xml = Data("""
    <rss xmlns:ht="https://trends.google.com/trending/rss"><channel><item>
    <title>ISRO launch</title><link>https://trends.google.com/</link>
    <pubDate>Mon, 19 Oct 2026 20:10:00 -0700</pubDate>
    <ht:news_item>
    <ht:news_item_title>Rocket launched</ht:news_item_title>
    <ht:news_item_snippet>Space organization completes mission</ht:news_item_snippet>
    <ht:news_item_url>https://example.com/rocket</ht:news_item_url>
    <ht:news_item_source>Space Desk</ht:news_item_source>
    </ht:news_item>
    </item></channel></rss>
    """.utf8)
    let client = TrendingHashtagClient(
        configuration: TrendingConfiguration(timeWindowHours: nil),
        transport: CountingFixtureTransport(responses: [.success(xml)])
    )
    let hashtags = try await client.trendingHashtags()
    #expect(hashtags.first?.hashtag == "#ISROlaunch")
    #expect(hashtags.first?.title == "Rocket launched")
    #expect(hashtags.first?.shortDescription == "Space organization completes mission")
    #expect(hashtags.first?.article?.source == "Space Desk")
    #expect(hashtags.first?.platform == .googleTrends)
}

@Test func rejectsEmptyAndMalformedFeeds() async throws {
    let empty = TrendingHashtagClient(transport: CountingFixtureTransport(responses: [.success(Data("<rss/>".utf8))]))
    await #expect(throws: TrendingHashtagError.self) { try await empty.trendingHashtags() }
    let malformed = TrendingHashtagClient(transport: CountingFixtureTransport(responses: [.success(Data("<rss>".utf8))]))
    await #expect(throws: TrendingHashtagError.self) { try await malformed.trendingHashtags() }
}

@Test func surfacesHTTPFailureAndRejectsInvalidLimits() async throws {
    let client = TrendingHashtagClient(transport: CountingFixtureTransport(responses: [.failure(.httpStatus(429))]))
    do {
        _ = try await client.trendingHashtags()
        Issue.record("Expected HTTP error")
    } catch TrendingHashtagError.httpStatus(let status) {
        #expect(status == 429)
    }
    await #expect(throws: TrendingHashtagError.self) { try await client.trendingHashtags(limit: 101) }
    await #expect(throws: TrendingHashtagError.self) { try await client.trendingHashtags(limit: 0) }
}

@Test func deduplicatesTopicsAndKeepsTopicsWithoutArticles() async throws {
    let xml = Data("""
    <rss><channel>
    <item><title>Space launch</title></item>
    <item><title>space launch</title></item>
    <item><title>Cricket</title></item>
    </channel></rss>
    """.utf8)
    let client = TrendingHashtagClient(
        configuration: TrendingConfiguration(timeWindowHours: nil),
        transport: CountingFixtureTransport(responses: [.success(xml)])
    )
    let hashtags = try await client.trendingHashtags(limit: 1)
    #expect(hashtags.count == 1)
    #expect(hashtags[0].hashtag == "#Spacelaunch")
    #expect(hashtags[0].article == nil)
}

@Test func filtersByConfigurableTimeWindow() async throws {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

    let now = Date()
    let recentDateStr = formatter.string(from: now.addingTimeInterval(-2 * 3600)) // 2 hours ago
    let oldDateStr = formatter.string(from: now.addingTimeInterval(-30 * 3600)) // 30 hours ago

    let xml = Data("""
    <rss><channel>
    <item><title>Recent Topic</title><pubDate>\(recentDateStr)</pubDate></item>
    <item><title>Old Topic</title><pubDate>\(oldDateStr)</pubDate></item>
    </channel></rss>
    """.utf8)

    // Default time window is 24 hours -> Recent Topic should pass, Old Topic should be filtered out
    let client24 = TrendingHashtagClient(
        configuration: TrendingConfiguration(timeWindowHours: 24),
        transport: CountingFixtureTransport(responses: [.success(xml)])
    )
    let topics24 = try await client24.trendingHashtags()
    #expect(topics24.count == 1)
    #expect(topics24[0].topic == "Recent Topic")

    // Custom time window of 1 hour -> both should be filtered out -> throws noResults
    let client1 = TrendingHashtagClient(
        configuration: TrendingConfiguration(timeWindowHours: 1),
        transport: CountingFixtureTransport(responses: [.success(xml)])
    )
    await #expect(throws: TrendingHashtagError.self) { try await client1.trendingHashtags() }

    // Time window nil -> both pass
    let clientAll = TrendingHashtagClient(
        configuration: TrendingConfiguration(timeWindowHours: nil),
        transport: CountingFixtureTransport(responses: [.success(xml)])
    )
    let topicsAll = try await clientAll.trendingHashtags()
    #expect(topicsAll.count == 2)
}

@Test func cachesResultsForConfiguredDuration() async throws {
    let xml = Data("""
    <rss><channel>
    <item><title>Caching Topic</title></item>
    </channel></rss>
    """.utf8)
    let transport = CountingFixtureTransport(responses: [.success(xml)])
    let client = TrendingHashtagClient(
        configuration: TrendingConfiguration(timeWindowHours: nil, cacheDuration: 6 * 3600),
        transport: transport
    )

    let firstFetch = try await client.trendingHashtags()
    #expect(firstFetch.count == 1)
    let count1 = await transport.callCount
    #expect(count1 == 1)

    // Second call within 6 hours should return cached results without additional transport request
    let secondFetch = try await client.trendingHashtags()
    #expect(secondFetch.count == 1)
    let count2 = await transport.callCount
    #expect(count2 == 1)

    // Force refresh bypasses cache and increments transport call count
    let thirdFetch = try await client.trendingHashtags(forceRefresh: true)
    #expect(thirdFetch.count == 1)
    let count3 = await transport.callCount
    #expect(count3 == 2)
}

@Test func filtersLanguagesAndDisregardsOtherLanguages() async throws {
    let xml = Data("""
    <rss><channel>
    <item><title>Chandrayaan 4</title></item>
    <item><title>चंद्रयान 4 सफल</title></item>
    <item><title>Sarkar ki nayi yojana ka ailan</title></item>
    <item><title>إطلاق الصاروخ اليوم</title></item>
    <item><title>Запуск ракеты сегодня</title></item>
    <item><title>விண்கலம் ஏவுதல் நிகழ்வு</title></item>
    </channel></rss>
    """.utf8)

    // Default configuration allows English, Hindi, and Hinglish, and disregards other languages
    let client = TrendingHashtagClient(
        configuration: TrendingConfiguration(timeWindowHours: nil),
        transport: CountingFixtureTransport(responses: [.success(xml)])
    )
    let tags = try await client.trendingHashtags()
    let topics = tags.map(\.topic)

    #expect(topics.contains("Chandrayaan 4"))
    #expect(topics.contains("चंद्रयान 4 सफल"))
    #expect(topics.contains("Sarkar ki nayi yojana ka ailan"))

    // Disregarded other languages
    #expect(!topics.contains("إطلاق الصاروخ اليوم"))
    #expect(!topics.contains("Запуск ракеты сегодня"))
    #expect(!topics.contains("விண்கலம் ஏவுதல் நிகழ்வு"))
}

@Test func findsTagDetailViaWikipediaAndFeed() async throws {
    let wikiJSON = Data("""
    {
      "title": "Sam Raimi",
      "description": "American filmmaker",
      "extract": "Samuel Marshall Raimi is an American filmmaker and actor.",
      "content_urls": {
        "desktop": {
          "page": "https://en.wikipedia.org/wiki/Sam_Raimi"
        }
      }
    }
    """.utf8)

    let transport = CustomHandlerTransport { url in
        if url.host?.contains("wikipedia.org") == true {
            return wikiJSON
        }
        throw TrendingHashtagError.httpStatus(404)
    }

    let client = TrendingHashtagClient(transport: transport)
    let detail = try await client.tagDetail(for: "#SamRaimi")

    #expect(detail.tag == "#SamRaimi")
    #expect(detail.title == "Sam Raimi")
    #expect(detail.shortDescription.contains("filmmaker"))
    #expect(detail.source == "Wikipedia")
    #expect(detail.url?.absoluteString == "https://en.wikipedia.org/wiki/Sam_Raimi")
}

@Test func supportsConfiguringVariousPlatformsWithGoogleAsDefault() async throws {
    // 1. Default platform is Google Trends
    let defaultClient = TrendingHashtagClient()
    #expect(defaultClient.platformProvider.platform == .googleTrends)

    // 2. Custom platform provider configuration
    let customProvider = CustomPlatformProvider(platform: .custom) { config, limit, transport in
        return [
            TrendingTopic(
                topic: "Custom Topic",
                hashtag: "#CustomTag",
                title: "Custom Title",
                shortDescription: "Custom Description",
                platform: .custom
            )
        ]
    }

    let customClient = TrendingHashtagClient(platformProvider: customProvider)
    #expect(customClient.platformProvider.platform == .custom)
    let customTags = try await customClient.trendingHashtags()
    #expect(customTags.first?.hashtag == "#CustomTag")
    #expect(customTags.first?.platform == .custom)

    // 3. Twitter provider option with endpoint
    let twitterJSON = Data("""
    {
      "trends": [
        {"name": "TwitterTrend", "tag": "#TwitterTrend", "description": "Trending on Twitter"}
      ]
    }
    """.utf8)
    let twitterTransport = CustomHandlerTransport { _ in twitterJSON }
    let twitterClient = TrendingHashtagClient(
        provider: .twitter(endpoint: URL(string: "https://example.com/twitter/trends")!),
        transport: twitterTransport
    )
    #expect(twitterClient.platformProvider.platform == .twitter)
    let twitterTags = try await twitterClient.trendingHashtags()
    #expect(twitterTags.first?.hashtag == "#TwitterTrend")
    #expect(twitterTags.first?.platform == .twitter)
}

@Test func backwardCompatibilityWithGoogleTrendsClient() async throws {
    let xml = Data("""
    <rss><channel>
    <item>
    <title>Festival of Lights</title>
    <ht:news_item>
    <ht:news_item_title>Diwali celebrations begin</ht:news_item_title>
    <ht:news_item_url>https://example.com/diwali</ht:news_item_url>
    <ht:news_item_source>Daily News</ht:news_item_source>
    </ht:news_item>
    </item>
    </channel></rss>
    """.utf8)

    let client = GoogleTrendsClient(
        transport: CountingFixtureTransport(responses: [.success(xml)]),
        configuration: TrendingConfiguration(timeWindowHours: nil)
    )

    let topics = try await client.trendingTopics(limit: 1)
    #expect(topics.count == 1)
    #expect(topics[0].hashtag == "#FestivalofLights")
    #expect(topics[0].article?.title == "Diwali celebrations begin")
    #expect(topics[0].article?.source == "Daily News")
}

import Foundation
import Testing
import GoogleTrendsSource

private struct TrendsFixtureTransport: TrendsTransport {
    let responses: [Result<Data, GoogleTrendsError>]
    init(_ responses: [Result<Data, GoogleTrendsError>]) { self.responses = responses }
    func data(from url: URL) async throws -> Data { try responses[0].get() }
}

@Test func parsesTrendArticleWithoutOverwritingTopic() async throws {
    let xml = Data("""
    <rss xmlns:ht="https://trends.google.com/trending/rss"><channel><item>
    <title>ISRO launch</title><link>https://trends.google.com/</link>
    <ht:news_item><ht:news_item_title>Rocket launched</ht:news_item_title><ht:news_item_url>https://example.com/rocket</ht:news_item_url><ht:news_item_source>Space Desk</ht:news_item_source></ht:news_item>
    <ht:news_item><ht:news_item_title>Other article</ht:news_item_title><ht:news_item_url>https://example.com/other</ht:news_item_url></ht:news_item>
    </item></channel></rss>
    """.utf8)
    let topics = try await GoogleTrendsClient(transport: TrendsFixtureTransport([.success(xml)])).trendingTopics()
    #expect(topics.first?.hashtag == "#ISROlaunch")
    #expect(topics.first?.article?.title == "Rocket launched")
    #expect(topics.first?.article?.source == "Space Desk")
}


@Test func rejectsEmptyAndMalformedFeeds() async throws {
    let empty = GoogleTrendsClient(transport: TrendsFixtureTransport([.success(Data("<rss/>".utf8))]))
    await #expect(throws: GoogleTrendsError.self) { try await empty.trendingTopics() }
    let malformed = GoogleTrendsClient(transport: TrendsFixtureTransport([.success(Data("<rss>".utf8))]))
    await #expect(throws: GoogleTrendsError.self) { try await malformed.trendingTopics() }
}

@Test func surfacesHTTPFailureAndRejectsInvalidLimits() async throws {
    let client = GoogleTrendsClient(transport: TrendsFixtureTransport([.failure(.httpStatus(429))]))
    do {
        _ = try await client.trendingTopics()
        Issue.record("Expected HTTP error")
    } catch GoogleTrendsError.httpStatus(let status) { #expect(status == 429) }
    await #expect(throws: GoogleTrendsError.self) { try await client.trendingTopics(limit: 101) }
}

@Test func deduplicatesTopicsAndKeepsTopicsWithoutArticles() async throws {
    let xml = Data("<rss><channel><item><title>Space launch</title></item><item><title>space launch</title></item><item><title>Cricket</title></item></channel></rss>".utf8)
    let client = GoogleTrendsClient(transport: TrendsFixtureTransport([.success(xml)]))
    let topics = try await client.trendingTopics(limit: 1)
    #expect(topics.count == 1)
    #expect(topics[0].hashtag == "#Spacelaunch")
    #expect(topics[0].article == nil)
}

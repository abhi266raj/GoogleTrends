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


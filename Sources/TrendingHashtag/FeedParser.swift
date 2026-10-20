// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct FeedItem: Sendable {
    var title = ""
    var description = ""
    var link = ""
    var source = ""
    var date = ""
    var approxTraffic = ""
    var relatedTitle = ""
    var relatedLink = ""
    var relatedSource = ""
    var relatedSnippet = ""

    var publishedAt: Date? {
        FeedParser.parseDate(date)
    }

    var article: TrendArticle? {
        makeArticle(title: title, link: link, source: source, snippet: description)
    }

    var relatedArticle: TrendArticle? {
        makeArticle(
            title: relatedTitle,
            link: relatedLink,
            source: relatedSource,
            snippet: !relatedSnippet.isEmpty ? relatedSnippet : (!description.isEmpty ? description : nil)
        )
    }

    private func makeArticle(title: String, link: String, source: String, snippet: String?) -> TrendArticle? {
        guard !title.isEmpty, let url = URL(string: link),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return TrendArticle(
            title: title,
            url: url,
            source: source.isEmpty ? (url.host ?? "") : source,
            publishedAt: publishedAt,
            snippet: snippet
        )
    }
}

/// Each parse owns its delegate. External entities are never resolved.
final class FeedParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var items: [FeedItem] = []
    private var current: FeedItem?
    private var path: [String] = []
    private var text = ""
    private var relatedDepth = 0
    private var capturedRelated = false

    private static let formatters: [DateFormatter] = {
        let posix = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        return formats.map { fmt in
            let df = DateFormatter()
            df.locale = posix
            df.dateFormat = fmt
            return df
        }
    }()

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    static func parse(_ data: Data) throws -> [FeedItem] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw TrendingHashtagError.malformedFeed(parser.parserError?.localizedDescription ?? "Invalid XML.")
        }
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        path.append(name)
        text = ""
        if name == "item" { current = FeedItem(); capturedRelated = false }
        if name == "news_item" { relatedDepth += 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = path.last ?? elementName
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current != nil {
            if relatedDepth > 0 && !capturedRelated {
                switch name {
                case "news_item_title": current?.relatedTitle = value
                case "news_item_snippet": current?.relatedSnippet = value
                case "news_item_url": current?.relatedLink = value
                case "news_item_source": current?.relatedSource = value
                default: break
                }
            } else if path.dropLast().last == "item" {
                switch name {
                case "title": current?.title = value
                case "description": current?.description = value
                case "link": current?.link = value
                case "source": current?.source = value
                case "pubDate": current?.date = value
                case "approx_traffic": current?.approxTraffic = value
                default: break
                }
            }
            if name == "news_item" {
                relatedDepth -= 1
                if current?.relatedArticle != nil { capturedRelated = true }
            }
            if name == "item", let item = current { items.append(item); current = nil }
        }
        if !path.isEmpty { path.removeLast() }
        text = ""
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public actor TrendingCache {
    private struct CacheEntry: Sendable {
        let topics: [TrendingTopic]
        let cachedAt: Date
    }

    private var storage: [String: CacheEntry] = [:]

    public init() {}

    public func get(key: String, validFor duration: TimeInterval, now: Date = Date()) -> [TrendingTopic]? {
        guard duration > 0, let entry = storage[key] else { return nil }
        if now.timeIntervalSince(entry.cachedAt) <= duration {
            return entry.topics
        }
        storage.removeValue(forKey: key)
        return nil
    }

    public func set(key: String, topics: [TrendingTopic], now: Date = Date()) {
        storage[key] = CacheEntry(topics: topics, cachedAt: now)
    }

    public func remove(key: String) {
        storage.removeValue(forKey: key)
    }

    public func clear() {
        storage.removeAll()
    }
}

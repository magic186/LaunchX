import Foundation

/// A simple thread-safe cache for search results to improve performance for frequent queries.
final class SearchCache {
    private struct CachedResult {
        let results: [SearchResult]
        var accessCount: Int
        var lastAccess: Date
    }

    private var cache: [String: CachedResult] = [:]
    private let maxCacheSize = 15
    private let lock = NSLock()

    /// Retrieve cached results for a specific query
    func getCachedResults(for query: String) -> [SearchResult]? {
        lock.lock()
        defer { lock.unlock() }

        return cache[query.lowercased()]?.results
    }

    /// Update access statistics for a cached query
    func recordAccess(for query: String) {
        lock.lock()
        defer { lock.unlock() }

        let key = query.lowercased()
        if var entry = cache[key] {
            entry.accessCount += 1
            entry.lastAccess = Date()
            cache[key] = entry
        }
    }

    /// Store search results in the cache
    func cacheResults(_ results: [SearchResult], for query: String, accessCount: Int = 1) {
        lock.lock()
        defer { lock.unlock() }

        let key = query.lowercased()

        // If cache is full, remove the least recently used item
        if cache.count >= maxCacheSize && cache[key] == nil {
            if let lruKey = cache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
                cache.removeValue(forKey: lruKey)
            }
        }

        cache[key] = CachedResult(
            results: results,
            accessCount: accessCount,
            lastAccess: Date()
        )
    }

    /// Clear all cached results
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

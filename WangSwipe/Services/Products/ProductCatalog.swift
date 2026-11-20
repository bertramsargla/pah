import Foundation

/// Pulls pages from every enabled provider at once and mixes them so the deck
/// alternates between stores instead of showing one store's whole catalog first.
actor ProductCatalog {
    private let providers: [any ProductProvider]
    private var nextPage: [String: Int] = [:]
    private var exhausted: Set<String> = []
    private var seen: Set<String> = []

    init(providers: [any ProductProvider]) {
        self.providers = providers
    }

    var isExhausted: Bool {
        providers.allSatisfy { exhausted.contains($0.id) }
    }

    /// Fetches the next page from each provider that still has items and
    /// returns them interleaved, skipping anything already returned.
    /// A provider that errors is skipped for this batch and tried again next time.
    func nextBatch() async -> [Product] {
        let active = providers.filter { !exhausted.contains($0.id) }
        guard !active.isEmpty else { return [] }

        let pages = active.map { nextPage[$0.id, default: 0] }
        let results = await withTaskGroup(of: (Int, Result<[Product], Error>).self) { group in
            for (index, provider) in active.enumerated() {
                let page = pages[index]
                group.addTask {
                    do {
                        return (index, .success(try await provider.fetchProducts(page: page)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[Product], Error>)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }
        }

        var lists: [[Product]] = []
        for (index, result) in results {
            let provider = active[index]
            switch result {
            case .success(let items):
                if items.isEmpty {
                    exhausted.insert(provider.id)
                } else {
                    nextPage[provider.id] = pages[index] + 1
                    lists.append(items)
                }
            case .failure:
                continue
            }
        }

        let fresh = Self.interleave(lists).filter { seen.insert($0.id).inserted }
        return fresh
    }

    /// Round-robin merge: a1, b1, c1, a2, b2, ...
    static func interleave(_ lists: [[Product]]) -> [Product] {
        let longest = lists.map(\.count).max() ?? 0
        var merged: [Product] = []
        merged.reserveCapacity(lists.reduce(0) { $0 + $1.count })
        for position in 0..<longest {
            for list in lists where position < list.count {
                merged.append(list[position])
            }
        }
        return merged
    }
}

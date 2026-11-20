import SwiftUI
import Observation

/// Puts a whole outfit on the user's photo: the upper garment first, then the
/// lower one on top of that result. Results are kept per outfit, so pressing
/// Dress Me again on the same outfit costs nothing.
@MainActor
@Observable
final class Dresser {
    enum State: Equatable {
        case idle
        case working(step: Int, of: Int, item: String)
        case ready(UIImage)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    private(set) var serviceLabel: String = ""

    @ObservationIgnored private var service: any TryOnService = MockTryOnService()
    @ObservationIgnored private var person: UIImage? = nil
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    private let garments = GarmentImageLoader()

    /// Call when the user's photo or the try-on backend changes. Drops all results.
    func configure(person: UIImage?, service: any TryOnService) {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        states = [:]
        self.person = person
        self.service = service
        serviceLabel = service.label
    }

    static func key(_ items: [Product]) -> String {
        items.map(\.id).joined(separator: "+")
    }

    func state(for items: [Product]) -> State {
        states[Self.key(items)] ?? .idle
    }

    /// Starts dressing unless this outfit is already done or in progress.
    func dress(_ items: [Product]) {
        let key = Self.key(items)
        switch state(for: items) {
        case .working, .ready: return
        case .idle, .failed: break
        }
        guard let person, !items.isEmpty else { return }
        let service = self.service
        let generation = self.generation
        states[key] = .working(step: 1, of: items.count, item: items[0].title)

        tasks[key] = Task { [weak self, garments] in
            var current = person
            do {
                for (index, item) in items.enumerated() {
                    self?.update(key, .working(step: index + 1, of: items.count, item: item.title), generation)
                    let garment = try await garments.image(for: item)
                    current = try await service.render(person: current, garment: garment, product: item)
                }
                self?.finish(key, .ready(current), generation)
            } catch is CancellationError {
                self?.finish(key, .idle, generation)
            } catch {
                self?.finish(key, .failed(error.localizedDescription), generation)
            }
        }
    }

    private func update(_ key: String, _ state: State, _ generation: Int) {
        guard generation == self.generation else { return }
        states[key] = state
    }

    private func finish(_ key: String, _ state: State, _ generation: Int) {
        guard generation == self.generation else { return }
        tasks[key] = nil
        states[key] = state
    }
}

/// Fetches (or draws) the garment image that gets sent to the try-on service.
@MainActor
final class GarmentImageLoader {
    private var cache: [Product.ID: UIImage] = [:]

    func image(for product: Product) async throws -> UIImage {
        if let cached = cache[product.id] { return cached }
        let image: UIImage
        if let url = product.imageURL {
            image = try await Self.download(url)
        } else {
            guard let drawn = GarmentArtView.renderImage(for: product) else { throw TryOnError.badImage }
            image = drawn
        }
        cache[product.id] = image
        return image
    }

    /// Store CDNs (Farfetch's especially) sometimes refuse a request, so try a few times.
    private static func download(_ url: URL, attempts: Int = 3) async throws -> UIImage {
        var lastError: Error = TryOnError.badImage
        for attempt in 0..<attempts {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(600 * attempt)) }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    lastError = TryOnError.httpStatus(http.statusCode, "garment photo")
                    continue
                }
                if let image = UIImage(data: data) { return image }
                lastError = TryOnError.badImage
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

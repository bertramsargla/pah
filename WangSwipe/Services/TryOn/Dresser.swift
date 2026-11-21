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
    /// When each outfit started dressing, for the live timer in the mirror.
    private(set) var startDates: [String: Date] = [:]
    /// Where the time went for each finished outfit, e.g. "14.2 s · photos 0.3 s · try-on 6.9 + 7.0 s".
    private(set) var timings: [String: String] = [:]
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
        startDates = [:]
        timings = [:]
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

    func startDate(for items: [Product]) -> Date? { startDates[Self.key(items)] }
    func timing(for items: [Product]) -> String? { timings[Self.key(items)] }

    /// Downloads the outfit's garment photos ahead of time so Dress Me starts
    /// the try-on right away. Free: no try-on call is made.
    func prefetch(_ items: [Product]) {
        Task { [garments] in
            for item in items { _ = try? await garments.image(for: item) }
        }
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
        states[key] = service.dressesWholeOutfit
            ? .working(step: 1, of: 1, item: "Whole outfit")
            : .working(step: 1, of: items.count, item: items[0].title)

        startDates[key] = .now
        timings[key] = nil

        tasks[key] = Task { [weak self, garments] in
            var current = person
            let clock = ContinuousClock()
            let started = clock.now
            var photoTime = Duration.zero
            var tryOnTimes: [Duration] = []
            do {
                if service.dressesWholeOutfit {
                    // One call for the whole outfit.
                    self?.update(key, .working(step: 1, of: 1, item: "Whole outfit"), generation)
                    var images: [UIImage] = []
                    let photoStart = clock.now
                    for item in items { images.append(try await garments.image(for: item)) }
                    photoTime = clock.now - photoStart
                    let tryOnStart = clock.now
                    current = try await service.renderOutfit(person: person, garments: images, products: items)
                    tryOnTimes.append(clock.now - tryOnStart)
                } else {
                    for (index, item) in items.enumerated() {
                        self?.update(key, .working(step: index + 1, of: items.count, item: item.title), generation)
                        let photoStart = clock.now
                        let garment = try await garments.image(for: item)
                        photoTime += clock.now - photoStart
                        let tryOnStart = clock.now
                        current = try await service.render(person: current, garment: garment, product: item)
                        tryOnTimes.append(clock.now - tryOnStart)
                    }
                }
                let summary = "\(Self.seconds(clock.now - started)) · photos \(Self.seconds(photoTime)) · "
                    + "try-on \(tryOnTimes.map(Self.seconds).joined(separator: " + "))"
                self?.record(key, summary, generation)
                self?.finish(key, .ready(current), generation)
            } catch is CancellationError {
                self?.finish(key, .idle, generation)
            } catch {
                self?.finish(key, .failed(error.localizedDescription), generation)
            }
        }
    }

    private func record(_ key: String, _ timing: String, _ generation: Int) {
        guard generation == self.generation else { return }
        timings[key] = timing
    }

    nonisolated static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.1f s", value)
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

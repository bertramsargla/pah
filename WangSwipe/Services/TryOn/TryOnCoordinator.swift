import SwiftUI
import Observation

/// Runs try-ons for the cards near the top of the deck, a couple at a time,
/// and remembers the results. Real models take several seconds per image, so
/// the deck asks for the next few cards ahead of time.
@MainActor
@Observable
final class TryOnCoordinator {
    enum State: Equatable {
        case idle
        case working
        case ready(UIImage)
        case failed(String)
    }

    private(set) var states: [Product.ID: State] = [:]
    private(set) var serviceLabel: String = ""
    var maxConcurrent = 2

    @ObservationIgnored private var service: any TryOnService = MockTryOnService()
    @ObservationIgnored private var person: UIImage? = nil
    @ObservationIgnored private var queue: [Product] = []
    @ObservationIgnored private var tasks: [Product.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    private let garments = GarmentImageLoader()

    /// Call when the user's photo or the try-on backend changes. Drops all results.
    func configure(person: UIImage?, service: any TryOnService) {
        generation += 1
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        queue = []
        states = [:]
        self.person = person
        self.service = service
        serviceLabel = service.label
    }

    func state(for product: Product) -> State {
        states[product.id] ?? .idle
    }

    /// Queues try-ons for any of these products that haven't been started.
    func request(_ products: [Product]) {
        for product in products where state(for: product) == .idle && !queue.contains(product) {
            queue.append(product)
        }
        pump()
    }

    func retry(_ product: Product) {
        states[product.id] = .idle
        request([product])
    }

    private func pump() {
        while tasks.count < maxConcurrent, !queue.isEmpty {
            start(queue.removeFirst())
        }
    }

    private func start(_ product: Product) {
        guard let person else { return }
        let service = self.service
        let generation = self.generation
        states[product.id] = .working
        tasks[product.id] = Task { [weak self, garments] in
            let outcome: State
            do {
                let garment = try await garments.image(for: product)
                let image = try await service.render(person: person, garment: garment, product: product)
                outcome = .ready(image)
            } catch is CancellationError {
                outcome = .idle
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            self?.finish(product.id, outcome, generation: generation)
        }
    }

    private func finish(_ id: Product.ID, _ state: State, generation: Int) {
        guard generation == self.generation else { return }
        tasks[id] = nil
        states[id] = state
        pump()
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
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let decoded = UIImage(data: data) else { throw TryOnError.badImage }
            image = decoded
        } else {
            guard let drawn = GarmentArtView.renderImage(for: product) else { throw TryOnError.badImage }
            image = drawn
        }
        cache[product.id] = image
        return image
    }
}

import XCTest
@testable import WangSwipe

final class ProductCatalogTests: XCTestCase {
    private func product(_ provider: String, _ n: Int) -> Product {
        Product(
            id: "\(provider):\(n)", providerID: provider, storeName: provider, title: "Item \(n)",
            brand: nil, price: 10, currencyCode: "USD", category: .top,
            imageURL: nil, productURL: nil, swatchHex: nil
        )
    }

    func testInterleaveIsRoundRobin() {
        let a = (0..<3).map { product("a", $0) }
        let b = (0..<1).map { product("b", $0) }
        let merged = ProductCatalog.interleave([a, b])
        XCTAssertEqual(merged.map(\.id), ["a:0", "b:0", "a:1", "a:2"])
    }

    func testCatalogPagesThroughAllProvidersThenStops() async {
        let a = MockStoreProvider(id: "a", displayName: "A", products: (0..<5).map { product("a", $0) }, pageSize: 2, latency: .zero)
        let b = MockStoreProvider(id: "b", displayName: "B", products: (0..<2).map { product("b", $0) }, pageSize: 2, latency: .zero)
        let catalog = ProductCatalog(providers: [a, b])

        var all: [Product] = []
        for _ in 0..<5 {
            all += await catalog.nextBatch()
        }
        XCTAssertEqual(all.count, 7)
        XCTAssertEqual(Set(all.map(\.id)).count, 7, "no duplicates")
        let exhausted = await catalog.isExhausted
        XCTAssertTrue(exhausted)
    }

    func testMockStoresAreNonEmptyAndUnique() {
        let ids = MockStores.all.flatMap { $0.products.map(\.id) }
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

final class CategoryTests: XCTestCase {
    func testInferCategory() {
        XCTAssertEqual(GarmentCategory.infer(from: "Short Sleeve T-Shirt"), .top)
        XCTAssertEqual(GarmentCategory.infer(from: "Cargo Shorts"), .bottom)
        XCTAssertEqual(GarmentCategory.infer(from: "Shirt Dress"), .dress)
        XCTAssertEqual(GarmentCategory.infer(from: "Shirt Jacket"), .outerwear)
        XCTAssertNil(GarmentCategory.infer(from: "Leather Belt"))
    }
}

final class ShopifyParsingTests: XCTestCase {
    func testParsesApparelAndSkipsOtherItems() throws {
        let json = """
        {"products": [
          {"id": 1, "title": "Linen Shirt", "handle": "linen-shirt", "vendor": "Acme",
           "product_type": "Shirts", "variants": [{"price": "49.00"}],
           "images": [{"src": "https://cdn.example.com/shirt.jpg"}]},
          {"id": 2, "title": "Gift Card", "handle": "gift-card", "vendor": "Acme",
           "product_type": "Gift Card", "variants": [{"price": "25.00"}], "images": []}
        ]}
        """
        let products = try ShopifyStoreProvider.parse(
            Data(json.utf8), domain: "shop.example.com", providerID: "shopify:shop.example.com", currencyCode: "USD"
        )
        XCTAssertEqual(products.count, 1)
        let shirt = try XCTUnwrap(products.first)
        XCTAssertEqual(shirt.id, "shopify:shop.example.com:1")
        XCTAssertEqual(shirt.category, .top)
        XCTAssertEqual(shirt.price, Decimal(string: "49.00"))
        XCTAssertEqual(shirt.productURL?.absoluteString, "https://shop.example.com/products/linen-shirt")
        XCTAssertEqual(shirt.imageURL?.absoluteString, "https://cdn.example.com/shirt.jpg")
    }
}

final class FalTryOnTests: XCTestCase {
    func testRequestBodyUsesEachModelsFieldNames() {
        let google = FalTryOnService.requestBody(model: .googleVTO, personImage: "p", garmentImage: "g")
        XCTAssertEqual(google["person_image_url"] as? String, "p")
        XCTAssertEqual(google["product_image_url"] as? String, "g")

        let kling = FalTryOnService.requestBody(model: .klingKolors, personImage: "p", garmentImage: "g")
        XCTAssertEqual(kling["human_image_url"] as? String, "p")
        XCTAssertEqual(kling["garment_image_url"] as? String, "g")
    }

    func testReadsResultURLFromEitherShape() throws {
        let list = Data(#"{"images": [{"url": "https://fal.media/a.png"}]}"#.utf8)
        XCTAssertEqual(try FalTryOnService.resultImageURL(from: list).absoluteString, "https://fal.media/a.png")

        let single = Data(#"{"image": {"url": "https://fal.media/b.png"}}"#.utf8)
        XCTAssertEqual(try FalTryOnService.resultImageURL(from: single).absoluteString, "https://fal.media/b.png")

        XCTAssertThrowsError(try FalTryOnService.resultImageURL(from: Data("{}".utf8)))
    }

    func testMissingKeyFailsWithoutCallingNetwork() async {
        let service = FalTryOnService(apiKey: "", model: .googleVTO)
        let image = UIImage(systemName: "person")!
        do {
            _ = try await service.render(person: image, garment: image, product: MockStores.northline.products[0])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TryOnError, .missingAPIKey)
        }
    }
}

final class SwipeAndMockTryOnTests: XCTestCase {
    func testSwipeDecision() {
        XCTAssertEqual(SwipeDirection.decide(translation: CGSize(width: 150, height: 0), predictedEnd: .zero, threshold: 100), .right)
        XCTAssertEqual(SwipeDirection.decide(translation: CGSize(width: -150, height: 0), predictedEnd: .zero, threshold: 100), .left)
        XCTAssertNil(SwipeDirection.decide(translation: CGSize(width: 40, height: 0), predictedEnd: CGSize(width: 60, height: 0), threshold: 100))
        XCTAssertEqual(SwipeDirection.decide(translation: CGSize(width: 40, height: 0), predictedEnd: CGSize(width: 300, height: 0), threshold: 100), .right)
    }

    func testMockTryOnReturnsImageTheSizeOfThePhoto() async throws {
        let person = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { ctx in
            UIColor.lightGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let garment = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 80)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
        }
        let service = MockTryOnService(latency: .zero)
        let result = try await service.render(person: person, garment: garment, product: MockStores.northline.products[0])
        XCTAssertEqual(result.size.width, person.size.width, accuracy: 1)
        XCTAssertEqual(result.size.height, person.size.height, accuracy: 1)
    }
}

@MainActor
final class DeckAndDemoTests: XCTestCase {
    func testDemoPhotoIsBundled() {
        XCTAssertNotNil(AppModel.demoPhoto)
    }

    func testPlainBackgroundSegmenterFindsTheDemoPerson() throws {
        let photo = try XCTUnwrap(AppModel.demoPhoto)
        let result = try XCTUnwrap(PlainBackgroundSegmenter.segment(photo))
        let body = result.body
        XCTAssertEqual(result.mask.width, Int(photo.size.width))
        // Shoulders sit in the upper third and the middle of the frame.
        XCTAssertLessThan(body.shoulderLeft.y, photo.size.height * 0.4)
        XCTAssertGreaterThan(body.shoulderLeft.x, photo.size.width * 0.15)
        XCTAssertLessThan(body.shoulderRight.x, photo.size.width * 0.85)
        XCTAssertGreaterThan(body.hipLeft.y, body.shoulderLeft.y)
    }

    func testFlattenRemovesTransparency() throws {
        let clear = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let flat = clear.flattened(on: .white)
        let data = try XCTUnwrap(flat.jpegData(compressionQuality: 1))
        let decoded = try XCTUnwrap(UIImage(data: data)?.cgImage)
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = context.data!.assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(pixel[0], 240, "transparent areas should become white, not black")
    }

    func testCategoryFilterShowsOnlyThatCategory() async {
        let deck = DeckViewModel(
            catalog: ProductCatalog(providers: MockStores.all.map { store in
                var fast = store
                fast.latency = .zero
                return fast
            }),
            tryOn: TryOnCoordinator()
        )
        deck.setFilter(.dress)
        await deck.loadMoreIfNeeded()
        XCTAssertFalse(deck.visibleCards.isEmpty)
        XCTAssertTrue(deck.visibleCards.allSatisfy { $0.category == .dress })
    }
}

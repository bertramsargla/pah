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

    func testCuratedCatalogIsTenMensPiecesWithLinksAndPhotos() {
        let products = CuratedStores.all.flatMap(\.products)
        XCTAssertEqual(products.count, 10)
        XCTAssertEqual(Set(products.map(\.id)).count, 10)
        XCTAssertTrue(products.allSatisfy { $0.imageURL != nil && $0.productURL != nil })
        XCTAssertFalse(products.contains { $0.category == .dress })
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

    func testFashnUsesFastModeAndTheRightCategory() {
        let top = FalTryOnService.requestBody(model: .fashn, personImage: "p", garmentImage: "g", category: .outerwear)
        XCTAssertEqual(top["model_image"] as? String, "p")
        XCTAssertEqual(top["garment_image"] as? String, "g")
        XCTAssertEqual(top["category"] as? String, "tops")
        XCTAssertEqual(top["mode"] as? String, "performance")
        let bottom = FalTryOnService.requestBody(model: .fashn, personImage: "p", garmentImage: "g", category: .bottom)
        XCTAssertEqual(bottom["category"] as? String, "bottoms")
    }

    func testNanoBananaSendsPhotoAndWholeOutfitInOneCall() {
        let products = Array(CuratedStores.all.flatMap(\.products).filter { $0.category != .bottom }.prefix(1))
            + Array(CuratedStores.all.flatMap(\.products).filter { $0.category == .bottom }.prefix(1))
        let body = FalTryOnService.outfitRequestBody(personImage: "p", garmentImages: ["top", "bottom"], products: products)
        XCTAssertEqual(body["image_urls"] as? [String], ["p", "top", "bottom"])
        let prompt = body["prompt"] as? String ?? ""
        XCTAssertTrue(prompt.contains("image 2 is the top"))
        XCTAssertTrue(prompt.contains("image 3 is the bottom"))
        XCTAssertTrue(FalTryOnModel.nanoBanana.dressesWholeOutfit)
        XCTAssertFalse(FalTryOnModel.fashn.dressesWholeOutfit)
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
            _ = try await service.render(person: image, garment: image, product: CuratedStores.fwrd.products[0])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TryOnError, .missingAPIKey)
        }
    }
}

final class MockTryOnTests: XCTestCase {
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
        let result = try await service.render(person: person, garment: garment, product: CuratedStores.fwrd.products[0])
        XCTAssertEqual(result.size.width, person.size.width, accuracy: 1)
        XCTAssertEqual(result.size.height, person.size.height, accuracy: 1)
    }
}

@MainActor
final class DemoPhotoTests: XCTestCase {
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
}

@MainActor
final class WardrobeTests: XCTestCase {
    private func loadedWardrobe() async -> WardrobeModel {
        let wardrobe = WardrobeModel(catalog: ProductCatalog(providers: CuratedStores.all))
        await wardrobe.load()
        return wardrobe
    }

    func testLoadsAllTenPiecesIntoTwoPanels() async {
        let wardrobe = await loadedWardrobe()
        XCTAssertEqual(wardrobe.products.count, 10)
        XCTAssertEqual(wardrobe.items(for: .upper).count + wardrobe.items(for: .lower).count, 10)
        XCTAssertTrue(wardrobe.items(for: .lower).allSatisfy { $0.category == .bottom })
        XCTAssertEqual(wardrobe.outfit.count, 2, "Dress Me gets an upper and a lower piece")
        XCTAssertEqual(OutfitSlot(wardrobe.outfit[0].category), .upper)
        XCTAssertEqual(OutfitSlot(wardrobe.outfit[1].category), .lower)
    }

    func testSkipMovesOnePanelAndWrapsAround() async {
        let wardrobe = await loadedWardrobe()
        let uppers = wardrobe.items(for: .upper)
        let lowerBefore = wardrobe.current(.lower)
        wardrobe.skip(.upper, by: 1)
        XCTAssertEqual(wardrobe.current(.upper)?.id, uppers[1].id)
        XCTAssertEqual(wardrobe.current(.lower)?.id, lowerBefore?.id, "the other panel stays put")
        wardrobe.skip(.upper, by: -2)
        XCTAssertEqual(wardrobe.current(.upper)?.id, uppers.last?.id, "going back from the first wraps to the last")
    }

    func testShuffleAlwaysChangesTheOutfit() async {
        let wardrobe = await loadedWardrobe()
        for _ in 0..<25 {
            let before = wardrobe.outfit.map(\.id)
            wardrobe.shuffle()
            XCTAssertEqual(wardrobe.outfit.count, 2)
            XCTAssertNotEqual(wardrobe.outfit.map(\.id), before)
        }
    }

    func testPlayShufflesOnATimerUntilStopped() async throws {
        let wardrobe = await loadedWardrobe()
        wardrobe.playInterval = .milliseconds(50)
        let before = wardrobe.outfit.map(\.id)
        wardrobe.togglePlay()
        XCTAssertTrue(wardrobe.isPlaying)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNotEqual(wardrobe.outfit.map(\.id), before)
        wardrobe.togglePlay()
        XCTAssertFalse(wardrobe.isPlaying)
        let stopped = wardrobe.outfit.map(\.id)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(wardrobe.outfit.map(\.id), stopped, "nothing changes after pause")
    }

    func testSectionFiltersOnlyItsPanel() async {
        let wardrobe = await loadedWardrobe()
        XCTAssertEqual(Set(wardrobe.availableSections), [.shirts, .sweaters, .jackets, .jeans])
        wardrobe.select(.jackets)
        XCTAssertEqual(wardrobe.items(for: .upper).count, 4)
        XCTAssertTrue(wardrobe.items(for: .upper).allSatisfy { $0.category == .outerwear })
        XCTAssertEqual(wardrobe.items(for: .lower).count, 2, "lower panel is unaffected")
        wardrobe.select(.jackets)
        XCTAssertNil(wardrobe.section, "tapping the same section again clears it")
    }

    func testMensSections() {
        func section(_ title: String, _ category: GarmentCategory) -> MensSection {
            MensSection.of(Product(id: title, providerID: "t", storeName: "T", title: title, brand: nil, price: 1,
                                   currencyCode: "USD", category: category, imageURL: nil, productURL: nil, swatchHex: nil))
        }
        XCTAssertEqual(section("Union Rugby Shirt", .top), .shirts)
        XCTAssertEqual(section("The Chalet Sweater", .top), .sweaters)
        XCTAssertEqual(section("Silk Satin Bomber", .outerwear), .jackets)
        XCTAssertEqual(section("Straight-Leg Jeans", .bottom), .jeans)
        XCTAssertEqual(section("Pleated Trousers", .bottom), .pants)
    }
}

/// Records each call so the test can see the outfit was put on in order.
private actor CallLog {
    var titles: [String] = []
    func add(_ title: String) { titles.append(title) }
}

private struct RecordingTryOnService: TryOnService {
    let log: CallLog
    var label: String { "Test" }
    func render(person: UIImage, garment: UIImage, product: Product) async throws -> UIImage {
        await log.add(product.title)
        return person
    }
}

/// Dresses the whole outfit in one call and records how it was called.
private struct OneCallTryOnService: TryOnService {
    let log: CallLog
    var label: String { "Test" }
    var dressesWholeOutfit: Bool { true }
    func render(person: UIImage, garment: UIImage, product: Product) async throws -> UIImage {
        await log.add("single:" + product.title)
        return person
    }
    func renderOutfit(person: UIImage, garments: [UIImage], products: [Product]) async throws -> UIImage {
        await log.add("outfit:" + products.map(\.title).joined(separator: "+"))
        return person
    }
}

@MainActor
final class DresserTests: XCTestCase {
    private func product(_ title: String, _ category: GarmentCategory) -> Product {
        Product(id: title, providerID: "t", storeName: "T", title: title, brand: nil, price: 1,
                currencyCode: "USD", category: category, imageURL: nil, productURL: nil, swatchHex: "#335577")
    }

    private func waitUntilDone(_ dresser: Dresser, _ outfit: [Product]) async throws {
        for _ in 0..<100 {
            switch dresser.state(for: outfit) {
            case .ready, .failed: return
            default: try await Task.sleep(for: .milliseconds(50))
            }
        }
        XCTFail("dresser never finished")
    }

    func testDressPutsOnTopThenBottomAndCachesTheLook() async throws {
        let log = CallLog()
        let dresser = Dresser()
        let person = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { _ in }
        dresser.configure(person: person, service: RecordingTryOnService(log: log))
        let outfit = [product("Shirt", .top), product("Jeans", .bottom)]

        dresser.dress(outfit)
        try await waitUntilDone(dresser, outfit)
        guard case .ready = dresser.state(for: outfit) else { return XCTFail("expected a finished look") }
        let calls = await log.titles
        XCTAssertEqual(calls, ["Shirt", "Jeans"])

        dresser.dress(outfit)
        try await Task.sleep(for: .milliseconds(100))
        let again = await log.titles
        XCTAssertEqual(again.count, 2, "pressing Dress Me again on the same outfit reuses the result")
    }

    func testWholeOutfitServiceIsCalledOnce() async throws {
        let log = CallLog()
        let dresser = Dresser()
        let person = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 40)).image { _ in }
        dresser.configure(person: person, service: OneCallTryOnService(log: log))
        let outfit = [product("Shirt", .top), product("Jeans", .bottom)]
        dresser.dress(outfit)
        try await waitUntilDone(dresser, outfit)
        let calls = await log.titles
        XCTAssertEqual(calls, ["outfit:Shirt+Jeans"])
    }

    func testDressWithoutAPhotoDoesNothing() {
        let dresser = Dresser()
        dresser.configure(person: nil, service: MockTryOnService(latency: .zero))
        let outfit = [product("Shirt", .top)]
        dresser.dress(outfit)
        XCTAssertEqual(dresser.state(for: outfit), .idle)
    }
}

final class SkinTests: XCTestCase {
    func testThreeSkinsWithTheRequestedNames() {
        XCTAssertEqual(Skin.allCases.map(\.displayName), ["Clueless (1995) Wang Meme", "The Matrix (1999)", "Doom (1993)"])
        XCTAssertEqual(Skin.clueless.next, .matrix)
        XCTAssertEqual(Skin.doom.next, .clueless)
    }

    func testOlderSavedSettingsKeepTheirValuesAndGetTheDefaultSkin() throws {
        let old = #"{"tryOnBackend":"fal","falModel":"google/virtual-try-on","disabledStoreIDs":["grailed"],"shopifyDomains":[]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.tryOnBackend, .fal)
        XCTAssertEqual(settings.disabledStoreIDs, ["grailed"])
        XCTAssertEqual(settings.skin, .clueless)
    }

    func testSkinRoundTrips() throws {
        var settings = AppSettings()
        settings.skin = .doom
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.skin, .doom)
    }
}

final class StylistTests: XCTestCase {
    private var context: StylistContext {
        let products = CuratedStores.all.flatMap(\.products)
        return StylistContext(wardrobe: products, showing: Array(products.prefix(2)), kept: [], photo: nil, look: nil)
    }

    func testRequestUsesGeminiNeonWithMediumThinking() throws {
        XCTAssertTrue(GeminiStylist.endpoint.absoluteString.contains("/models/gemini-4-neon:streamGenerateContent"))
        XCTAssertTrue(GeminiStylist.endpoint.absoluteString.hasSuffix("alt=sse"))
        let history = [ChatMessage(role: .user, text: "Hi", sentText: "On screen now: x.\n\nHi")]
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { _ in }
        let data = try GeminiStylist.requestBody(history: history, context: context, firstImages: [photo])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let system = try XCTUnwrap(body["systemInstruction"] as? [String: Any])
        let systemText = (system["parts"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        XCTAssertTrue(systemText.contains("Moncler"))
        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        let thinking = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        XCTAssertEqual(thinking["thinkingLevel"] as? String, "medium")
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertNotNil(parts.first?["inlineData"])
        XCTAssertEqual(parts.last?["text"] as? String, "On screen now: x.\n\nHi")
    }

    func testPhotosOnlyOnTheFirstMessage() throws {
        let history = [
            ChatMessage(role: .user, text: "Hi"),
            ChatMessage(role: .assistant, text: "Hello"),
            ChatMessage(role: .user, text: "And shoes?")
        ]
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { _ in }
        let data = try GeminiStylist.requestBody(history: history, context: context, firstImages: [photo])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.map { $0["role"] as? String }, ["user", "model", "user"])
        let last = try XCTUnwrap(contents.last?["parts"] as? [[String: Any]])
        XCTAssertEqual(last.count, 1)
        XCTAssertEqual(last.first?["text"] as? String, "And shoes?")
    }

    func testParsesStreamEvents() {
        XCTAssertEqual(GeminiStylist.parse(#"data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hey"}]}}]}"#), .text("Hey"))
        XCTAssertEqual(GeminiStylist.parse(#"data: {"candidates":[{"content":{"parts":[{"text":"hmm","thought":true}]}}]}"#), .other)
        XCTAssertEqual(GeminiStylist.parse(#"data: {"candidates":[{"content":{"parts":[{"text":"!"}]},"finishReason":"STOP"}]}"#), .text("!"))
        XCTAssertEqual(GeminiStylist.parse(#"data: {"candidates":[{"finishReason":"STOP"}]}"#), .done)
        XCTAssertEqual(GeminiStylist.parse(#"data: {"candidates":[{"finishReason":"SAFETY"}]}"#), .refused)
        XCTAssertEqual(GeminiStylist.parse(#"data: {"promptFeedback":{"blockReason":"SAFETY"}}"#), .refused)
        XCTAssertEqual(GeminiStylist.parse(#"data: {"error":{"code":503,"message":"Overloaded"}}"#), .failed("Overloaded"))
        XCTAssertEqual(GeminiStylist.parse(""), .other)
        XCTAssertEqual(GeminiStylist.errorMessage(in: #"{"error":{"code":400,"message":"API key not valid"}}"#), "API key not valid")
    }

    func testScreenNoteNamesWhatIsShowing() {
        let note = GeminiStylist.screenNote(context)
        XCTAssertTrue(note.hasPrefix("On screen now: "))
        XCTAssertTrue(note.contains(" + "))
    }
}

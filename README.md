# WangSwipe

An iPhone app (SwiftUI, iOS 17+) where you add a photo of yourself, then swipe
through clothes from several stores, Tinder style. Each card shows the item
virtually tried on you. Swipe right to save it, left to pass.

## Run it

You need a Mac with Xcode 15 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate        # creates WangSwipe.xcodeproj from project.yml
open WangSwipe.xcodeproj
```

Pick an iPhone simulator and press Run. To install on your own phone, select
your team under Signing & Capabilities first.

Tests: `xcodebuild test -scheme WangSwipe -destination 'platform=iOS Simulator,name=iPhone 16'`
(use any simulator you have installed).

Out of the box the deck shows 10 hand-picked men's pieces from FWRD, Grailed
and Farfetch (`Services/Products/CuratedStores.swift`; photos load from the stores'
CDNs, and Shop opens the real product page) with the free on-device preview,
so it needs no keys and costs nothing. Grailed pieces are one-off resale
listings and can sell at any time. The first screen starts with a
bundled demo photo selected (`DemoPerson` in the asset catalog), so a demo is
one tap. To skip onboarding entirely, launch with `-demoMode YES`
(Xcode: Product > Scheme > Edit Scheme > Arguments, or
`xcrun simctl launch booted com.wangswipe.app -demoMode YES`).

## Look

The UI is styled as an early-90s "virtual wardrobe" computer: navy title bars,
periwinkle display panels, beveled buttons, procedural leopard print, chunky
monospaced type and faint scanlines. The pieces live in `Shared/Retro.swift`.
Swipe right (or **Dress Me**) to keep an item, left (or **Pass**) to skip, and
filter by garment type with the strip at the bottom.

## How it fits together

```
WangSwipe/
  App/            WangSwipeApp (entry, tabs), AppModel (photo, likes, settings, wiring)
  Features/
    Onboarding/   add your photo (library or camera)
    Deck/         swipe deck, card view, deck model
    Liked/        saved items with links to buy
    Settings/     change photo, pick try-on engine and key, turn stores on/off
  Services/
    Products/     ProductProvider protocol, ProductCatalog (mixes stores), curated FWRD, Grailed + Farfetch picks, Shopify
    TryOn/        TryOnService protocol, mock (on device), fal.ai (hosted models), coordinator
    Storage/      photo on disk, API key in Keychain
```

Two seams make the app pluggable:

- **`ProductProvider`**: anything that returns pages of `Product`. The catalog
  pulls from every enabled provider at once and alternates between stores.
  Included: the curated FWRD, Grailed and Farfetch demo catalog, and `ShopifyStoreProvider`, which reads a
  Shopify store's public product list. Add a provider and register it in
  `ProviderRegistry`.
- **`TryOnService`**: takes your photo and a garment image and returns you
  wearing it. Included: `MockTryOnService` (free, finds your shoulders and hips
  with Apple's Vision and lays the item over them; a stand-in, not a real try-on)
  and `FalTryOnService` (calls Google Virtual Try-On or Kling Kolors on fal.ai).
  `AppModel.makeTryOnService()` picks one.

`TryOnCoordinator` prepares try-ons for the next three cards, two at a time,
because hosted models take several seconds per image.

## Turning on real try-on

Real try-on costs money per image, so it's off by default. To try it:
create a fal.ai account and key, then in the app go to Settings, set Engine to
fal.ai, pick a model and paste the key. The key is saved in the phone's
Keychain, never in this repo.

Before a public release, move the try-on call to your own server (the key must
not ship in the app), add a consent screen for sending body photos to a third
party, and set a retention policy. See [docs/PROVIDERS.md](docs/PROVIDERS.md)
for the options and prices that were checked.

## Next steps

- Real product feeds: an affiliate network feed served by a small backend (see docs).
- A backend that holds keys, caches try-on results per (photo, product), and tracks cost.
- Product filters (category, size, price) and an undo for the last swipe.

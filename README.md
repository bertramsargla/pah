# WangSwipe

An iPhone app (SwiftUI, iOS 17+) where you add a photo of yourself, then flip
through men's clothes from several stores on a 90s-style "wardrobe computer":
a top panel and a bottom panel, each with back / play / forward buttons.
**Shuffle** picks a random outfit, **Play** deals a new random outfit every
3 seconds, and **Dress Me** puts the whole outfit on your photo (virtual try-on).

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

Out of the box the wardrobe holds 10 hand-picked men's pieces from FWRD, Grailed
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
Launch opens on a loading screen of glowing wire hangers (`Features/Launch`).

There are three UI skins, picked from a dropdown in Setup or from the box in
the wardrobe's title bar (`Shared/Skin.swift`). Switching replays the hanger
loading screen in the new skin.

- **Clueless (1995) Wang Meme**: lavender panels, navy bars, leopard print.
- **The Matrix (1999)**: phosphor green on black with falling code.
- **Doom (1993)**: riveted rusty metal, blood-red buttons and a flickering fire glow.

All three are drawn in code (no images, logos or fonts from the films or the game).

On the wardrobe screen:

- The top panel holds shirts, sweaters and jackets; the bottom panel holds pants and jeans.
- ◀◀ and ▶▶ skip back or ahead one piece in that panel right away (swiping the picture works too).
- ▶ plays a new random outfit every 3 seconds; press it again to pause.
- **Shuffle** jumps to one random outfit.
- **Dress Me** puts the top on your photo, then the bottom on that result, and
  shows the look in a mirror window. **Keep** saves both pieces to the Closet tab.
- The strip at the bottom (SHIRTS SWEATERS JACKETS PANTS JEANS) narrows that
  section's panel to one kind; **MORE** shows everything again. Sections with
  nothing in them are dimmed.

## How it fits together

```
WangSwipe/
  App/            WangSwipeApp (entry, tabs), AppModel (photo, likes, settings, wiring)
  Features/
    Launch/       hanger loading screen
    Onboarding/   add your photo (library or camera)
    Wardrobe/     two-panel wardrobe screen, its model, and the Dress Me mirror
    Liked/        saved items with links to buy
    Settings/     change photo, pick try-on engine and key, turn stores on/off
  Services/
    Products/     ProductProvider protocol, ProductCatalog (mixes stores), curated FWRD, Grailed + Farfetch picks, Shopify
    TryOn/        TryOnService protocol, mock (on device), fal.ai (hosted models), Dresser (puts on a whole outfit)
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
  and `FalTryOnService` (calls Google Virtual Try-On, FASHN, Nano Banana or Kling Kolors on fal.ai).
  `AppModel.makeTryOnService()` picks one.

`Dresser` runs try-on only when you press Dress Me, one garment after the
other (top, then bottom on the result), and keeps each finished look so the
same outfit is never paid for twice. With fal.ai, Google's model takes about
35 s per piece; FASHN v1.6 (fast mode) should take a few seconds per piece at
the same price; Nano Banana dresses the whole outfit in one call (about $0.04)
but is a general image editor, so faces and poses may drift.

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
- More filters (size, price) and shoes, once a try-on model handles footwear well.

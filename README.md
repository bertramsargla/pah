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
loading screen in the new skin, with that skin's logo spinning and pulsing in
the middle (`LogoClueless`, `LogoMatrix`, `LogoDoom` in the asset catalog).

- **Clueless (1995) Wang Meme**: lavender panels, navy bars, leopard print.
- **The Matrix (1999)**: phosphor green on black with falling code.
- **Doom (1993)**: riveted rusty metal, blood-red buttons and a flickering fire glow.

The skins themselves are drawn in code. The Matrix and Doom logos on the
loading screen are the film's and the game's own artwork, supplied for this
private demo; they're copyrighted and trademarked, so replace them before any
public release.

On the wardrobe screen:

- The top panel holds shirts, sweaters and jackets; the bottom panel holds pants and jeans.
- ◀◀ and ▶▶ skip back or ahead one piece in that panel right away (swiping the picture works too).
- ▶ plays a new random outfit every 3 seconds; press it again to pause.
- **Shuffle** jumps to one random outfit.
- **Dress Me** puts the top on your photo, then the bottom on that result, and
  shows the look in a mirror window. **Keep** marks both pieces as kept, which the Agent knows about.
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
    Agent/        chat with an AI stylist (Gemini) about the wardrobe and your outfit
    Settings/     change photo, pick try-on engine and key, turn stores on/off
  Services/
    Products/     ProductProvider protocol, ProductCatalog (mixes stores), curated FWRD, Grailed + Farfetch picks, Shopify
    Agent/        GeminiStylist: streams replies from the Gemini API
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

`Dresser` runs try-on only when you press Dress Me, either in one call for the
whole outfit or one garment after the other (the free preview), and keeps each
finished look so the same outfit is never paid for twice. The app uses Nano Banana on fal.ai
(`AppModel.tryOnModel`): it dresses the whole outfit in one call, about $0.04,
and was the fastest when compared side by side with Google's try-on (about 35 s
per piece) and FASHN. It's a general image editor, so faces and poses can drift
a little. The other models are still in `FalTryOnModel` if you want to switch back.

## The Agent tab

The Agent tab is a chat with a stylist powered by Google's Gemini 4 Neon
(`gemini-4-neon` through the Gemini API's `streamGenerateContent`, medium
thinking level). It gets the wardrobe list, what's on screen, the pieces you
kept, and (on the first message) your photo and latest try-on. Its one starter
chip is "Find me the perfect match". When the agent recommends a whole outfit,
it ends its reply with a hidden `OUTFIT: <top id> | <bottom id>` line, and the
chat shows a Dress Me button under it that switches to the wardrobe, turns both
panels to those pieces and tries them on (the same paid try-on as the wardrobe's
own Dress Me). Add a Gemini API key in Setup; it's
stored in the Keychain and each reply is billed to that Google account
(about $3 per million input tokens and $15 per million output tokens). As with
try-on, move this call to your own server before a public release.

## Turning on real try-on

Real try-on costs money per image, so it's off by default. To try it:
create a fal.ai account and key, then in the app go to Settings, set Engine to
fal.ai and paste the key. The key is saved in the phone's
Keychain, never in this repo.

Before a public release, move the try-on call to your own server (the key must
not ship in the app), add a consent screen for sending body photos to a third
party, and set a retention policy. See [docs/PROVIDERS.md](docs/PROVIDERS.md)
for the options and prices that were checked.

## Next steps

- Real product feeds: an affiliate network feed served by a small backend (see docs).
- A backend that holds keys, caches try-on results per (photo, product), and tracks cost.
- More filters (size, price) and shoes, once a try-on model handles footwear well.

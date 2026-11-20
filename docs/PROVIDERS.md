# Try-on models and product sources

Checked November 20, 2026. Prices change; confirm on the vendor's page before
committing to one.

## Virtual try-on

All of these take a photo of a person and a photo of a garment and return an
image of the person wearing it. The app's `FalTryOnService` supports the two
marked "wired up"; the others need a few lines in `FalTryOnModel` and
`FalTryOnService.requestBody`.

| Model (fal.ai endpoint) | Price | Inputs | Notes |
|---|---|---|---|
| Google Virtual Try-On (`google/virtual-try-on`), wired up | $0.075 per image | `person_image_url`, `product_image_url`, `num_images` (1-4) | Output `images[].url`. |
| Kling Kolors v1.5 (`fal-ai/kling/v1-5/kolors-virtual-try-on`), wired up | $0.07 per image | `human_image_url`, `garment_image_url` | Keeps pose, skin tone and body shape. |
| FASHN v1.6 | $0.075 per image | `model_image`, `garment_image`, `category`, `mode` | 864x1296 output, good with prints and text on garments; quality modes. |
| FASHN v1.5 (`fal-ai/fashn/tryon/v1.5`) | $0.075 per image | as above | 576x864 output; commercial use allowed. |
| image-apps-v2 virtual try-on | $0.04 per image | `person_image_url`, `clothing_image_url` | Cheapest listed. |
| FLUX Virtual Try-On Pro (`fal-ai/flux-pro/v1/vto`) | about $0.04+ per image, billed per megapixel | person + garment + styling prompt | |
| Leffa (`fal-ai/leffa/virtual-tryon`) | $0.10 per image | `garment_type`: upper_body, lower_body, dresses | |
| Decart Lucy 2.1 VTON | $0.02 per second | live video | Real-time camera try-on, not single photos. |
| CatVTON | per compute second | | Research license only, not for a commercial app. |

Google's model is also available directly on Google Cloud (Vertex AI / Gemini
Enterprise "Virtual Try-On"), which may suit you if you already use Google
Cloud. The fal.ai route was chosen for the scaffold because one key reaches
several models.

Checked with a real call (Google Virtual Try-On): image inputs accept base64
data URIs, so the app sends photos without hosting them first. One image took
about 35 seconds.

**Cost sense check:** at $0.07 per image, a full outfit (top + bottom) is two
calls, about $0.14 per Dress Me. The app only calls the model when Dress Me is
pressed and reuses the result for the same outfit. A real launch still needs
server-side caching (same photo + same product = same result) and a spend cap.

Sources: [fal.ai try-on comparison](https://fal.ai/learn/tools/best-virtual-try-on-apis-2026) (written by fal, so treat rankings as marketing; prices are theirs),
[Google Virtual Try-On on fal](https://fal.ai/models/google/virtual-try-on/llms.txt),
[FASHN v1.5 on fal](https://fal.ai/models/fal-ai/fashn/tryon/v1.5).

## Clothing from many stores

| Source | How it works | Fit for this app |
|---|---|---|
| Affiliate network product feeds (CJ, Rakuten, Awin, Impact) | Apply as a publisher, get approved by each brand, download product feeds (title, price, image, deep link). You earn commission on sales. | Best path for a real app: legal, many brands, pays you. Needs a backend to pull and normalize feeds. |
| Feed aggregators (for example FMTC getProducts) | One API over many networks' feeds. | Faster than joining networks one by one; paid. |
| Shopify public `/products.json` | Many Shopify stores expose it without a key. | Good for prototyping with stores that agree. Some stores turn it off, and their terms apply. Built into the app as `ShopifyStoreProvider`. |
| Direct brand partnerships | The brand gives you a feed or API. | Highest quality images (flat-lay shots work best for try-on), slow to set up. |

Try-on quality depends a lot on the garment photo: a flat-lay or
"ghost mannequin" shot on a plain background works much better than a model
photo. Affiliate feeds often include several images per product; prefer the
flat one.

Further reading (from search, not reviewed in depth): [Shopify on affiliate APIs](https://www.shopify.com/blog/affiliate-api),
[FMTC getProducts](https://www.fmtc.co/getproducts-api-product-feed/),
[affiliate.com on networks](https://affiliate.com/networks).

## Recommended next step

A small backend (one service) that:

1. Pulls one or two affiliate feeds nightly and serves them as pages of `Product` JSON.
2. Holds the try-on key, calls the model, and caches results by (photo hash, product id).
3. Logs cost per user.

The app then needs one new `ProductProvider` (pointing at your feed endpoint)
and one new `TryOnService` (pointing at your try-on endpoint). Nothing else changes.

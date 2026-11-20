# Harvest Basket — Grocery Restock Agent (Senso.ai Hackathon)

Built for the Senso.ai challenge: **"Build a shopping agent with trusted context."**

Harvest Basket is a fictional grocery retailer. The agent's primary job is **restocking**: given
a household's order history and preferences, it decides what they need to reorder this cycle. Its
secondary job is **price-sensitive comparison**: when an item has multiple brand/size options, it
picks the one that best fits the household's stated budget and dietary preferences and explains
the price/price-per-unit tradeoff, instead of just grabbing the first match. The full trail behind
every decision — what it searched for, what it retrieved (with citations), what it fact-checked,
and what action it took — is shown live in the UI.

## How it uses Senso

- **Context stored**: `backend/context/*.md` — grocery catalog (with brand/size price variants),
  household profile (allergies, brand/budget preferences), order history (past orders +
  consumption notes), and store policy (substitutions, delivery minimum, allergy handling) —
  ingested as raw documents via `POST /org/kb/raw`.
- **Retrieval**: the agent calls `POST /org/search/context` for every decision that depends on
  catalog facts, past orders, preferences, or policy, and logs each citation (`content_id`,
  `kb_node_id`, `chunk_text`, `score`, `rank`) to the audit trail panel.
- **Verification**: before giving the shopper a final answer, the agent sends its draft to
  `POST /org/evals/text` (Senso's fact-check). Verdicts (`verified`/`conflict`/`unsupported`/
  `not_verifiable`) are shown in the trail; the agent corrects conflicting claims and flags
  unsupported ones instead of asserting them. **Two things we learned from testing this live, not
  just reading the docs**:
  1. Fact-check only scores a claim once Senso knows what "your brand" is — without a brand
     kit, every claim about Harvest Basket comes back `about_brand: false`, `passed: null`
     (silently unscored, not an error). `ingest.py` calls `PUT /org/brand-kit` with
     `brand_name: "Harvest Basket Grocery"` before ingesting content, which is what makes real
     verdicts (verified / conflict / unsupported) show up instead of nulls.
  2. Even with a brand kit set, a claim only gets scored if it's tied to *Harvest Basket* in the
     text. "Terra Verde olive oil costs $12.99" comes back unscored (`about_brand: false`), but
     "Harvest Basket sells Terra Verde olive oil at $12.99" comes back `verified`. Claims about the
     customer ("this is excluded for your household") stay unscored or `unsupported` however
     they're phrased, because they're inferences, not catalog facts. `agent.py`'s system prompt
     tells the agent to phrase price claims as "Harvest Basket sells X at $Y", and to back
     customer-specific reasoning with `search_context` citations instead.
- **Action**: the agent calls a small mock storefront (`backend/mock_store.py`) to add items to
  a cart and check out. Senso does not complete purchases — per the challenge FAQ, that's the
  app's job — so every mock-store action is labeled `mode: "simulated"` in the trail and the UI.
  As a defense-in-depth safety net, the mock store also hard-blocks any item matching the
  household's tree-nut allergy flag, independent of what the agent decides.

## Architecture

```
frontend/index.html        single-page chat UI + live audit-trail panel (no build step)
backend/
  senso_client.py          REST wrapper: /org/me, /org/kb/raw, /org/kb/nodes/{id},
                           /org/search, /org/search/context, /org/evals/text, /org/evals/runs/{id}
  context/*.md             the fictional context to ingest
    products.md              grocery catalog, with brand/size price variants for comparison
    household_profile.md     allergies, dietary notes, brand & budget preferences
    order_history.md         past orders + consumption-pattern notes
    store_policy.md          delivery, substitution, and allergy-handling policy
  ingest.py                pushes context/*.md into Senso, polls until processed
  mock_store.py            in-memory catalog + cart/checkout, allergy hard-block, all actions simulated
  agent.py                 Claude tool-use loop: search_context, list_products, add_to_cart,
                           checkout, fact_check — logs every call to `trail`
  main.py                  FastAPI app exposing POST /api/chat
```

## Setup

1. Sign up at https://docs.senso.ai/docs/overview, create an org (choose "Knowledge Base for
   Agents"), and get an API key at https://docs.senso.ai/api-keys. Credits are pre-loaded.
2. Get an Anthropic API key (console.anthropic.com) for the agent's own reasoning.
3. Copy `.env.example` to `.env` in `backend/` (or project root) and fill in both keys.

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python ingest.py        # pushes the fictional context into your Senso org
uvicorn main:app --reload --port 8000
```

4. Open `frontend/index.html` directly in a browser (or serve it with any static server).

## Try it

- **Restock (primary)**: "It's been about 2 weeks since our last order, can you restock what we
  usually need?" → agent should reason from order history (milk ×2, eggs, bread, sunflower seed
  butter, paper towels are reordered every cycle; rice and GF bread are not always needed),
  respect the tree-nut allergy (picks sunflower seed butter, never peanut/tree-nut items), prefer
  store brand for everyday basics, keep the Terra Verde olive-oil exception, and simulate adding
  items to cart.
- **Price comparison (secondary)**: "We're almost out of peanut butter and olive oil — what
  should we get?" → agent should compare price-per-unit across brand options, apply the
  household's "store brand for basics, except olive oil" rule, and avoid the peanut butter option
  entirely because of the allergy — picking sunflower seed butter instead and explaining why.
- **Missing info**: ask something order history doesn't cover (e.g. "should we get more rice this
  time?") → agent should say the pattern doesn't clearly establish that rather than guessing.
- **Fact-check catch**: ask the agent to justify a questionable claim (e.g. "are store-brand eggs
  cage-free?") → the fact-check step should flag it as conflict/unsupported rather than confirming.

## Notes

- All brand names, products, prices and policies are invented for this demo (per the challenge
  rules).
- This is single-session/demo-grade: one shared cart and conversation per backend process, no
  auth, no persistence. Fine for a hackathon demo, not for production.

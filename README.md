# Harvest Basket: a grocery agent that shows its work (Senso.ai hackathon)

Built for the Senso.ai challenge: **"Build a shopping agent with trusted context."**

Harvest Basket is a fictional grocery store. Its shopping agent **restocks** a household's usual
order from their order history and preferences, and does **price-sensitive comparison** when an
item has several brands or sizes. Every fact it relies on comes from Senso's context layer, every
answer is fact-checked by Senso before checkout, and the trail behind each decision (searches,
citations, verdicts, cart actions) is shown to the shopper.

## What to open

| | What it is | How to open it |
|---|---|---|
| **Shop app** | What a shopper uses: catalog, cart, and the assistant with "How I decided" panels | `http://localhost:8000/shop` (live), or open it with no server for recorded examples |
| **Agent console** | Developer view: chat plus the raw audit trail and checkout gate | `http://localhost:8000/` |
| **Dashboard** | Stats from the recorded runs: verdicts, citations, carts, thresholds | Claude artifact (link in the PR) |

## How it uses Senso

- **Context**: `backend/context/*.md` (catalog with brand and size variants, household profile,
  order history, store policy) is ingested with `POST /org/kb/raw`.
- **Retrieval**: the agent calls `POST /org/search/context` for every decision and the trail keeps
  each citation's `content_id`, `kb_node_id`, `version_id`, `chunk_text`, `score` and `rank`.
- **Verification**: before checkout the agent sends its full draft answer to
  `POST /org/evals/text`. Each claim comes back `verified`, `conflict`, `unsupported` or unscored.
- **Action**: a mock storefront (`backend/mock_store.py`) holds the cart. Senso doesn't complete
  purchases, so every cart action is labelled simulated.

## Guards enforced in code, not just the prompt

1. **Checkout gate** (`backend/tools.py`). `checkout` refuses unless a fact-check ran after the
   last cart change, its drafts named every cart item, and the latest check found no conflicts.
   Refusals are logged to the trail with the reason.
2. **Re-check of unsupported claims.** Senso's judge isn't fully deterministic: the same claim came
   back `unsupported` in one run and `verified` in another. Unsupported claims are re-checked once;
   what still fails is shown to the shopper as unconfirmed.
3. **Allergy hard-block.** The store refuses any item tagged with the household's tree-nut allergy
   flag, whatever the agent asks for.
4. **Approve, then pay.** The agent's `checkout` only prepares a plan version (basket, subtotal,
   the Senso check behind it). Placing the order takes `approve_plan`, which only the shopper's app
   calls (`POST /api/plan/approve`); it is not one of the agent's tools. Any change to the basket or
   to the shopper's rules voids a waiting plan, and approving the same plan twice returns the same
   order instead of placing a second one.
5. **Your rules.** Shoppers add rules in plain words in the app ("Eggs must be cage-free"). The
   agent reads them with `get_preferences` at the start of every turn and treats them as hard
   requirements, checking the product facts they depend on with Senso.

Tests for all of the above, with Senso stubbed: `cd backend && python -m pytest -q tests`.

## Two agent backends, same tools

- **`claude-code`** (default without an API key): runs Claude Code headless (`claude -p`) with
  every built-in tool turned off and only the shop's MCP tools (`backend/mcp_server.py`) allowed.
  It uses the machine's Claude login, so no separate API key is needed.
- **`api`** (default when `ANTHROPIC_API_KEY` is set): calls the Claude API directly with tool use
  (`backend/agent.py`).

Both share `backend/tools.py` and `backend/prompt.py` and write the same trail, so the UI can't
tell them apart.

## What we learned about Senso while building

- **A brand kit is required for fact-checks to score anything.** Without one, every claim comes
  back `about_brand: false` with no verdict. `ingest.py` sets `PUT /org/brand-kit` to "Harvest
  Basket Grocery" first.
- **Claims are scored only when tied to the store.** Phrasing like "Harvest Basket sells X at $Y"
  usually gets name-brand prices scored, but not always. Claims about the shopper ("you bought
  rice on Oct 23") are never scored, so the agent must back them with search citations.
- **A waiting fact-check takes up to a minute.** The client allows 120 s; at 30 s every full-cart
  check timed out and the agent fell back to checking a few claims at a time.

## Architecture

```
frontend/
  shop.html            shopper-facing app (live or recorded examples)
  examples.json        recorded live sessions, built by backend/build_examples.py
  index.html           agent console with the raw trail
backend/
  context/*.md         the fictional knowledge base
  ingest.py            sets the brand kit, ingests context, waits for processing
  senso_client.py      REST wrapper for the Senso endpoints above
  tools.py             the agent's tools, state file, checkout gate, re-check
  prompt.py            system prompt and tool schemas
  mcp_server.py        the tools as an MCP server, for the Claude Code backend
  agent_claude_code.py Claude Code headless backend
  agent.py             Claude API backend
  mock_store.py        catalog, cart, allergy block (simulated)
  main.py              FastAPI: /shop, /, /api/chat, /api/state, /api/cart/add, /api/reset
  build_examples.py    turns recorded /api/chat responses into frontend/examples.json
```

## Setup

1. Create a Senso org at https://docs.senso.ai/docs/overview ("Knowledge Base for Agents") and an
   API key at https://docs.senso.ai/api-keys.
2. Put `SENSO_API_KEY` in `backend/.env`. Add `ANTHROPIC_API_KEY` to use the API backend, or have
   Claude Code installed and logged in to use the Claude Code backend.

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python ingest.py
uvicorn main:app --port 8000
```

Then open `http://localhost:8000/shop`.

## Try it

- **Restock**: "It's been about 2 weeks since our last order. Can you restock what we usually need
  and check out?"
- **Price comparison**: "We're almost out of peanut butter and olive oil. What should we get, and
  why?"
- **Unsafe request**: "Add the store-brand peanut butter since it's the cheapest, plus two dozen of
  the store-brand cage-free eggs, then check out." In the recorded run the agent refused the peanut
  butter (shared lines with tree nuts), Senso flagged a claim in its first draft as a conflict, and
  the agent rewrote and re-checked it before asking two questions. Adding that peanut butter by
  hand is refused by the store's allergy block.

## Notes

- The `reference/occasions-agent` branch is an unmodified copy of another team's project (Pantry by
  Shivay Lamba), kept for reference only. It has no license, so none of its code is in `main`; the
  approve-then-pay and rules ideas above were re-implemented here.
- All brands, products, prices and policies are invented for the demo.
- One demo session per server process, no auth. Fine for a hackathon, not for production.

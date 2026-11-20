"""The shopping agent: a Claude tool-use loop grounded in Senso's Context Layer.

Every tool call and its result is appended to `trail`, which is the audit
trail the hackathon challenge asks for: what context the agent retrieved
(with Senso's citation fields), what it fact-checked, and what action it
took.
"""

import json
import os
import time
import uuid

from anthropic import Anthropic

from mock_store import MockStore
from senso_client import SensoClient

MODEL = os.environ.get("AGENT_MODEL", "claude-sonnet-4-5")

SYSTEM_PROMPT = """You are the Harvest Basket Grocery shopping assistant. Harvest Basket is a \
fictional grocery retailer built for a hackathon demo. Your main job is RESTOCKING: given a \
household's order history and preferences, decide what they need to reorder this cycle and build \
the cart. Your secondary job is PRICE-SENSITIVE COMPARISON: when an item has multiple brand/size \
options, pick the one that best matches the household's stated preferences and budget, and \
explain the tradeoff (price, price-per-unit, and why) rather than just grabbing the first option.

You help the shopper using ONLY trusted context retrieved from the Senso knowledge base (via \
search_context) plus the mock_store tools for taking actions. Harvest Basket's real catalog, \
prices, household profile (dietary restrictions/allergies, brand and budget preferences), order \
history, and store policy all live in Senso, not in your own memory - never state a price, \
policy, allergen fact, or past-order fact unless it came back from search_context in this \
conversation. Mock store tool results about cart contents are authoritative for exact cart totals.

Rules:
1. Before deciding what to restock or recommend, call search_context with focused queries - e.g. \
one for the household's order history/consumption pattern, one for dietary restrictions and \
brand/budget preferences, one for the specific product category's price options, one for store \
policy if relevant (substitutions, delivery minimum, allergy handling).
2. Allergies are non-negotiable: if the household profile records an allergy (e.g. tree nut), \
NEVER add or recommend a product that matches that allergen or is made on a shared line with it, \
even as a substitution or secondary option. If you're unsure whether an item is safe, say so \
instead of guessing, and don't add it.
3. For items with multiple brand/size options, compare price-per-unit and pick based on the \
household's stated preference (e.g. "prefer store brand for everyday basics unless there's a \
noted exception"). State the price comparison you based the choice on.
4. Before you give the shopper your final recommendation or any answer that asserts facts, call \
fact_check with the exact text you are about to say, author="ai_assistant", and the shopper's \
request as question. Read the verdicts:
   - If any claim is "conflict", correct it before responding - don't repeat the wrong claim.
   - If any claim is "unsupported", say plainly that you couldn't confirm it rather than stating \
it as fact.
   - "verified" claims can be stated normally.
   - A claim can come back with no verdict at all (null/"general", about_brand=false) even when \
it's true and grounded in search_context - this happens for claims about a name-brand item \
(e.g. a third-party brand Harvest Basket stocks) rather than about Harvest Basket itself, and for \
claims about the customer/order history rather than the brand. That's expected Senso behavior, \
not a failure: for those claims, rely on the citations search_context already gave you rather \
than waiting on a fact_check verdict that won't arrive. Naming "Harvest Basket" explicitly in a \
claim about one of its own products or policies is what gets it scored.
5. If the context doesn't contain the answer to something necessary to proceed (e.g. it's unclear \
whether an item is due for restocking, or a budget tradeoff is ambiguous), ask the shopper a \
clarifying question or say what's missing instead of guessing.
6. Only take a shopping action (add_to_cart, checkout) once you have enough grounded information \
to justify it. Mock store actions are SIMULATED - always say so plainly when you take one; never \
imply a real purchase, payment, or delivery occurred.
7. Be concise and concrete. State which items you're restocking or recommending and why, citing \
the order history, preference, or policy that matters.
"""

TOOLS = [
    {
        "name": "search_context",
        "description": (
            "Search the Senso knowledge base for Trailhead Outfitters context (products, "
            "prices, stock, return policy, shipping policy, customer notes). Returns the raw "
            "retrieved passages with citation metadata (content_id, kb_node_id, score, rank) "
            "for your own reasoning - it does not write an answer for you."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string", "description": "A focused natural-language query."}},
            "required": ["query"],
        },
    },
    {
        "name": "list_products",
        "description": "List all products in the mock storefront (sku, name, price, unit, brand_tier, dietary/allergen tags).",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "add_to_cart",
        "description": (
            "Add a product to the household's cart in the mock store. Simulated action. "
            "The store will hard-block any item that matches an allergen on the account's "
            "allergy flag, regardless of what you request."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "sku": {"type": "string"},
                "qty": {"type": "number", "default": 1},
                "no_substitutions": {"type": "boolean", "default": False},
            },
            "required": ["sku"],
        },
    },
    {
        "name": "checkout",
        "description": "Check out the current cart in the mock store. Simulated action - no real payment occurs.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "fact_check",
        "description": (
            "Send a draft piece of your answer to Senso to verify every factual claim in it "
            "against the knowledge base. Call this on your draft BEFORE sending a final answer "
            "that states facts to the shopper. Uses no Senso credits."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "The exact draft text to check."},
                "question": {"type": "string", "description": "The shopper's original request."},
            },
            "required": ["text"],
        },
    },
]


class ShoppingAgent:
    def __init__(self, senso_client: SensoClient | None = None, store: MockStore | None = None):
        self.anthropic = Anthropic()  # reads ANTHROPIC_API_KEY from env
        self.senso = senso_client or SensoClient()
        self.store = store or MockStore()
        self.messages: list[dict] = []
        self.trail: list[dict] = []

    def _log(self, kind: str, **fields):
        self.trail.append({"id": str(uuid.uuid4()), "ts": time.time(), "kind": kind, **fields})

    def _dispatch(self, name: str, tool_input: dict) -> dict:
        if name == "search_context":
            query = tool_input["query"]
            result = self.senso.search_context(query)
            citations = [
                {
                    "content_id": r.get("content_id"),
                    "kb_node_id": r.get("kb_node_id"),
                    "content_chunk_id": r.get("content_chunk_id"),
                    "chunk_text": r.get("chunk_text"),
                    "score": r.get("score"),
                    "rank": r.get("rank"),
                }
                for r in result.get("results", [])
            ]
            self._log("senso_search_context", query=query, citations=citations)
            return result
        if name == "list_products":
            result = self.store.list_products()
            self._log("mock_store", action="list_products", result=result)
            return result
        if name == "add_to_cart":
            result = self.store.add_to_cart(**tool_input)
            self._log("mock_store", action="add_to_cart", input=tool_input, result=result)
            return result
        if name == "checkout":
            result = self.store.checkout()
            self._log("mock_store", action="checkout", result=result)
            return result
        if name == "fact_check":
            result = self.senso.check_text(
                text=tool_input["text"],
                author="ai_assistant",
                question=tool_input.get("question"),
                wait=True,
            )
            self._log("senso_fact_check", draft=tool_input["text"], question=tool_input.get("question"), result=result)
            return result
        raise ValueError(f"Unknown tool: {name}")

    def run_turn(self, user_message: str, max_steps: int = 8) -> dict:
        self.messages.append({"role": "user", "content": user_message})
        self._log("user_message", text=user_message)

        for _ in range(max_steps):
            response = self.anthropic.messages.create(
                model=MODEL,
                max_tokens=1500,
                system=SYSTEM_PROMPT,
                tools=TOOLS,
                messages=self.messages,
            )
            self.messages.append({"role": "assistant", "content": response.content})

            tool_uses = [b for b in response.content if b.type == "tool_use"]
            if not tool_uses:
                reply = "".join(b.text for b in response.content if b.type == "text")
                self._log("agent_reply", text=reply)
                return {"reply": reply, "trail": self.trail, "cart": self.store.cart.to_dict()}

            tool_results = []
            for block in tool_uses:
                try:
                    result = self._dispatch(block.name, block.input)
                except Exception as exc:  # surface tool errors to the model instead of crashing
                    result = {"error": str(exc)}
                tool_results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(result, default=str),
                    }
                )
            self.messages.append({"role": "user", "content": tool_results})

        self._log("agent_reply", text="(stopped after max_steps without a final answer)")
        return {
            "reply": "I'm having trouble finishing this request - please try rephrasing.",
            "trail": self.trail,
            "cart": self.store.cart.to_dict(),
        }

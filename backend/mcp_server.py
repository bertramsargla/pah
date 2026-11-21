"""MCP server exposing the shop tools, so Claude Code can act as the agent.

Run by agent_claude_code.py with SHOP_STATE pointing at the session's state file.
"""

import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))

from mcp.server.mcpserver import MCPServer  # noqa: E402

from tools import ToolBox  # noqa: E402

server = MCPServer("shop", instructions="Harvest Basket Grocery store tools and the Senso context layer.")


def _call(method: str, **kwargs):
    box = ToolBox(os.environ["SHOP_STATE"])
    try:
        return getattr(box, method)(**kwargs)
    except Exception as exc:
        box.log(method, ", ".join(f"{k}={str(v)[:60]}" for k, v in kwargs.items()) or method, f"Error: {exc}"[:300], "error")
        return {"error": f"{type(exc).__name__}: {exc}"[:500]}
    finally:
        box.save()


@server.tool()
def search_context(query: str) -> dict:
    """Search the Senso knowledge base (catalog, prices, household profile, order history, store policy). Returns passages with document, score and rank."""
    return _call("search_context", query=query)


@server.tool()
def list_products() -> dict:
    """List every product in the store: sku, name, price, unit, brand tier, allergen tags."""
    return _call("list_products")


@server.tool()
def add_to_cart(sku: str, qty: float = 1, no_substitutions: bool = False) -> dict:
    """Add a product to the simulated cart. The store hard-blocks items matching the account's allergy flag."""
    return _call("add_to_cart", sku=sku, qty=qty, no_substitutions=no_substitutions)


@server.tool()
def remove_from_cart(sku: str) -> dict:
    """Remove every line for a sku from the simulated cart."""
    return _call("remove_from_cart", sku=sku)


@server.tool()
def ask_shopper(item: str, question: str) -> dict:
    """Record a question for the shopper about an item the context doesn't settle. Ask it in your reply; don't add the item."""
    return _call("ask_shopper", item=item, question=question)


@server.tool()
def fact_check(text: str, question: str = "") -> dict:
    """Check every factual claim in your draft answer against the knowledge base with Senso. Required before checkout."""
    return _call("fact_check", text=text, question=question or None)


@server.tool()
def get_preferences() -> dict:
    """Read the preferences the shopper set in the app. Hard requirements; call at the start of every turn."""
    return _call("get_preferences")


@server.tool()
def checkout() -> dict:
    """Prepare a plan version of the simulated cart for the shopper to approve. Locked until a fact_check after the last cart change names every item with no conflicts. You cannot approve or pay."""
    return _call("checkout")


if __name__ == "__main__":
    server.run()

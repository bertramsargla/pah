"""The shopping agent's tools, shared by every agent backend.

State (cart, audit trail, last fact-check, open questions) lives in one JSON
file so a tool call made from the MCP server process and the web backend see
the same thing. Every call reloads the file and saves it after.

The fact-check gate is enforced here, in code: checkout refuses unless a
fact-check ran after the last cart change and found no conflicting claims.
"""

import difflib
import json
import pathlib
import re
import time

from mock_store import CATALOG, Cart, CartLine, MockStore
from senso_client import SensoClient

CONTEXT_IDS = pathlib.Path(__file__).parent / "context_ids.json"


def _doc_titles() -> dict:
    if not CONTEXT_IDS.exists():
        return {}
    return {v["id"]: v["title"] for v in json.loads(CONTEXT_IDS.read_text()).values()}


def _similar(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio()


def _words(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def _names(sku: str, text_words: set[str]) -> bool:
    """True when a draft names this product: most words of its name, minus size and house brand."""
    name = re.sub(r"\s*\(.*\)\s*$", "", CATALOG[sku]["name"]).replace("Harvest Basket ", "")
    words = [w for w in _words(name) if len(w) > 2]
    return bool(words) and sum(w in text_words for w in words) / len(words) >= 0.6


class ToolBox:
    def __init__(self, state_path, senso: SensoClient | None = None):
        self.state_path = pathlib.Path(state_path)
        self._senso = senso
        self.store = MockStore()
        self.trail: list[dict] = []
        self.questions: list[dict] = []
        self.cart_version = 0
        self.last_check: dict | None = None
        self.turn = 0
        self.load()

    @property
    def senso(self) -> SensoClient:
        if self._senso is None:
            self._senso = SensoClient()
        return self._senso

    def load(self):
        if not self.state_path.exists():
            return
        s = json.loads(self.state_path.read_text())
        self.store.cart = Cart(lines=[CartLine(**l) for l in s["cart"]["lines"]], checked_out=s["cart"]["checked_out"], order_id=s["cart"]["order_id"])
        self.store._order_counter = s.get("order_counter", 0)
        self.trail = s.get("trail", [])
        self.questions = s.get("questions", [])
        self.cart_version = s.get("cart_version", 0)
        self.last_check = s.get("last_check")
        self.turn = s.get("turn", 0)

    def save(self):
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.state_path.with_suffix(".tmp")
        tmp.write_text(json.dumps({
            "cart": {"lines": [l.__dict__ for l in self.store.cart.lines], "checked_out": self.store.cart.checked_out, "order_id": self.store.cart.order_id},
            "order_counter": self.store._order_counter,
            "trail": self.trail,
            "questions": self.questions,
            "cart_version": self.cart_version,
            "last_check": self.last_check,
            "turn": self.turn,
        }, indent=1, default=str))
        tmp.replace(self.state_path)

    def snapshot(self) -> dict:
        return {"trail": self.trail, "cart": self.store.cart.to_dict(), "questions": self.questions, "last_check": self.last_check}

    def log(self, tool: str, summary: str, outcome: str, status: str, **details):
        self.trail.append({"step": len(self.trail) + 1, "turn": self.turn, "ts": time.time(), "tool": tool, "summary": summary, "outcome": outcome, "status": status, **details})

    def start_turn(self, message: str):
        self.turn += 1
        self.log("shopper", message, "", "message")

    def end_turn(self, reply: str, **details):
        self.log("reply", reply, "", "message", **details)

    # ---- tools -------------------------------------------------------

    def search_context(self, query: str) -> dict:
        titles = _doc_titles()
        res = self.senso.search_context(query)
        citations = [{
            "content_id": r.get("content_id"),
            "kb_node_id": r.get("kb_node_id"),
            "version_id": r.get("version_id"),
            "content_chunk_id": r.get("content_chunk_id"),
            "document": titles.get(r.get("content_id"), "Unknown document"),
            "chunk_text": r.get("chunk_text"),
            "score": r.get("score"),
            "rank": r.get("rank"),
        } for r in res.get("results", [])]
        top = max((c["score"] or 0 for c in citations), default=0)
        self.log("search_context", query, f"{len(citations)} passages, top score {top:.2f}", "ok", citations=citations)
        return {"query": query, "results": [{k: c[k] for k in ("document", "chunk_text", "score", "rank", "content_id")} for c in citations]}

    def list_products(self) -> dict:
        self.log("list_products", "Catalog", f"{len(CATALOG)} products", "ok")
        return {"products": list(CATALOG.values()), "mode": "simulated"}

    def add_to_cart(self, sku: str, qty: float = 1, no_substitutions: bool = False) -> dict:
        r = self.store.add_to_cart(sku=sku, qty=qty, no_substitutions=no_substitutions)
        name = CATALOG.get(sku.upper(), {}).get("name", sku)
        if "error" in r:
            self.log("add_to_cart", f"{name} ×{qty:g}", r["error"], "blocked")
        else:
            self.cart_version += 1
            self.log("add_to_cart", f"{name} ×{qty:g}", f"Added. Subtotal ${self.store.cart.subtotal:.2f}", "ok")
        return r

    def remove_from_cart(self, sku: str) -> dict:
        before = len(self.store.cart.lines)
        self.store.cart.lines = [l for l in self.store.cart.lines if l.sku != sku.upper()]
        removed = before - len(self.store.cart.lines)
        if removed:
            self.cart_version += 1
        name = CATALOG.get(sku.upper(), {}).get("name", sku)
        self.log("remove_from_cart", name, "Removed" if removed else "Not in cart", "ok" if removed else "noop")
        return {"cart": self.store.cart.to_dict(), "removed": removed, "mode": "simulated"}

    def ask_shopper(self, item: str, question: str) -> dict:
        self.questions.append({"turn": self.turn, "item": item, "question": question})
        self.log("ask_shopper", item, question, "question")
        return {"recorded": True, "note": "Ask the shopper this in your reply. Do not add the item until they answer."}

    def _claims(self, result: dict) -> list[dict]:
        return [{"claim": c.get("claim_text", ""), "verdict": c.get("verdict") or "unscored", "evidence": (c.get("quote") or "")[:300], "reasoning": c.get("reasoning") or ""} for c in result.get("claims", [])]

    def _check(self, text: str, question: str | None) -> dict:
        r = self.senso.check_text(text=text, author="ai_assistant", question=question, wait=True)
        if r.get("status") != "completed" and r.get("eval_run_id"):
            r = self.senso.wait_for_eval(r["eval_run_id"])
        return r

    def fact_check(self, text: str, question: str | None = None) -> dict:
        first = self._check(text, question)
        claims = self._claims(first)
        recheck_id = None
        unsupported = [c for c in claims if c["verdict"] == "unsupported"]
        if unsupported:
            # Senso's judge is not fully deterministic: the same claim can come back
            # unsupported once and verified the next time. Re-check those claims once.
            second = self._check(" ".join(c["claim"] for c in unsupported), question)
            recheck_id = second.get("eval_run_id")
            re_claims = self._claims(second)
            for c in unsupported:
                best = max(re_claims, key=lambda r: _similar(r["claim"], c["claim"]), default=None)
                c["rechecked"] = True
                if best and _similar(best["claim"], c["claim"]) >= 0.75 and best["verdict"] in ("verified", "conflict"):
                    c["verdict"] = best["verdict"]
                    c["evidence"] = best["evidence"] or c["evidence"]
        conflicts = [c["claim"] for c in claims if c["verdict"] == "conflict"]
        unconfirmed = [c["claim"] for c in claims if c["verdict"] == "unsupported"]
        verified = sum(c["verdict"] == "verified" for c in claims)
        text_words = _words(text)
        covered = {l.sku for l in self.store.cart.lines if _names(l.sku, text_words)}
        if self.last_check and self.last_check["cart_version"] == self.cart_version:
            covered |= set(self.last_check.get("covered", []))
        missing = [l.name for l in self.store.cart.lines if l.sku not in covered]
        self.last_check = {
            "check_id": first.get("eval_run_id"), "recheck_id": recheck_id, "cart_version": self.cart_version,
            "conflicts": conflicts, "unconfirmed": unconfirmed, "verified": verified, "total": len(claims),
            "covered": sorted(covered), "missing": missing,
        }
        counts = {}
        for c in claims:
            counts[c["verdict"]] = counts.get(c["verdict"], 0) + 1
        self.log("fact_check", f"Draft answer, {len(claims)} claims", ", ".join(f"{n} {v}" for v, n in sorted(counts.items())),
                 "conflict" if conflicts else "ok", claims=claims, check_id=first.get("eval_run_id"), recheck_id=recheck_id, draft=text)
        return {
            "check_id": first.get("eval_run_id"),
            "claims": [{"claim": c["claim"], "verdict": c["verdict"]} for c in claims],
            "conflicts": conflicts,
            "unconfirmed": unconfirmed,
            "cart_items_not_yet_checked": missing,
            "checkout_allowed": not conflicts and not missing,
            "guidance": (
                "Conflicting claims contradict the knowledge base: correct them, then run fact_check again. "
                "Checkout stays locked until fact_checks after the last cart change name every cart item and the latest has no conflicts. "
                "Unconfirmed claims are not in the knowledge base: tell the shopper you couldn't confirm them. "
                "Unscored claims are about the shopper, not the store; back them with search_context citations."
            ),
        }

    def checkout(self) -> dict:
        lc = self.last_check
        if lc is None or lc["cart_version"] != self.cart_version:
            reason = "Checkout locked: run fact_check on your final answer after the last cart change, then try again."
            self.log("checkout", f"Subtotal ${self.store.cart.subtotal:.2f}", reason, "gated")
            return {"error": reason, "mode": "simulated"}
        if lc["conflicts"]:
            reason = "Checkout locked: the last fact_check found claims that conflict with the knowledge base: " + "; ".join(lc["conflicts"])
            self.log("checkout", f"Subtotal ${self.store.cart.subtotal:.2f}", reason, "gated")
            return {"error": reason, "mode": "simulated"}
        missing = [l.name for l in self.store.cart.lines if l.sku not in set(lc.get("covered", []))]
        if missing:
            reason = "Checkout locked: no fact_check since the last cart change named these cart items: " + "; ".join(missing)
            self.log("checkout", f"Subtotal ${self.store.cart.subtotal:.2f}", reason, "gated")
            return {"error": reason, "mode": "simulated"}
        r = self.store.checkout()
        if "error" in r:
            self.log("checkout", f"Subtotal ${self.store.cart.subtotal:.2f}", r["error"], "held")
        else:
            self.log("checkout", f"Subtotal ${self.store.cart.subtotal:.2f}", f"{r['order']['order_id']} (simulated, fact-check {lc['check_id'][:8]})", "ok")
        return r

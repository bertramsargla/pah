"""Tests for the rules enforced in code: checkout gate, approve-then-pay, preferences, allergy block.

Run from backend/:  python -m pytest -q tests
Senso is stubbed, so nothing here touches the network.
"""

import json
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import mcp_server  # noqa: E402
from prompt import TOOL_SPECS  # noqa: E402
from tools import ToolBox  # noqa: E402

BASKET = [("MILK-STORE-1G", 2), ("EGG-STORE-12", 1), ("PB-SUNFLOWER-16", 1), ("OLIVEOIL-NAME-17OZ", 1), ("PAPERTOWEL-STORE-6", 1)]
DRAFT = ("Harvest Basket sells Harvest Basket Whole Milk at $3.49, Harvest Basket Large Eggs at $3.29, "
         "SunSeed Sunflower Seed Butter at $6.99, Terra Verde Extra Virgin Olive Oil at $12.99 and "
         "Harvest Basket Paper Towels at $7.99.")


class FakeSenso:
    """Returns the queued verdict lists in order, one per check_text call."""

    def __init__(self, *runs):
        self.runs = list(runs) or [[("Harvest Basket sells milk at $3.49.", "verified")]]
        self.calls = 0

    def check_text(self, text, author, question, wait):
        verdicts = self.runs[min(self.calls, len(self.runs) - 1)]
        self.calls += 1
        return {"eval_run_id": f"run{self.calls:04d}", "status": "completed",
                "claims": [{"claim_text": c, "verdict": v} for c, v in verdicts]}


@pytest.fixture
def box(tmp_path):
    def make(*runs):
        return ToolBox(tmp_path / "state.json", senso=FakeSenso(*runs))
    return make


def fill(b):
    for sku, qty in BASKET:
        assert "cart" in b.add_to_cart(sku, qty)


def test_checkout_locked_without_fact_check(box):
    b = box()
    fill(b)
    r = b.checkout()
    assert "fact_check" in r["error"]
    assert b.trail[-1]["status"] == "gated"


def test_conflict_keeps_checkout_locked(box):
    b = box([("Harvest Basket store-brand eggs are cage-free.", "conflict")])
    fill(b)
    b.fact_check(DRAFT)
    assert "conflict" in b.checkout()["error"]


def test_draft_must_name_every_cart_item(box):
    b = box()
    fill(b)
    b.fact_check("Harvest Basket sells Harvest Basket Whole Milk at $3.49.")
    r = b.checkout()
    assert "named these cart items" in r["error"]
    assert "Paper Towels" in r["error"]


def test_unsupported_claim_is_rechecked(box):
    b = box([("Harvest Basket sells SunSeed at $6.99.", "unsupported")], [("Harvest Basket sells SunSeed at $6.99.", "verified")])
    fill(b)
    r = b.fact_check(DRAFT)
    assert r["claims"][0]["verdict"] == "verified"
    assert r["unconfirmed"] == []


def test_checkout_only_prepares_a_plan(box):
    b = box()
    fill(b)
    b.fact_check(DRAFT)
    r = b.checkout()
    assert r["status"] == "awaiting_approval" and r["plan_version"] == 1
    assert not b.store.cart.checked_out
    assert b.plans[0]["status"] == "awaiting_approval"


def test_checkout_twice_reuses_the_same_plan(box):
    b = box()
    fill(b)
    b.fact_check(DRAFT)
    b.checkout()
    assert b.checkout()["plan_version"] == 1
    assert len(b.plans) == 1


def test_shopper_approval_places_the_order(box):
    b = box()
    fill(b)
    b.fact_check(DRAFT)
    b.checkout()
    r = b.approve_plan(1)
    assert r["order_id"] == "DEMO-ORDER-0001" and not r["already_placed"]
    assert b.store.cart.checked_out
    assert b.trail[-1]["tool"] == "approve_plan" and b.trail[-1]["by"] == "shopper"


def test_approving_twice_does_not_order_twice(box):
    b = box()
    fill(b)
    b.fact_check(DRAFT)
    b.checkout()
    first = b.approve_plan(1)
    second = b.approve_plan(1)
    assert second["already_placed"] and second["order_id"] == first["order_id"]
    assert b.store._order_counter == 1


def test_basket_change_voids_the_plan(box):
    b = box()
    fill(b)
    b.fact_check(DRAFT)
    b.checkout()
    b.add_to_cart("BREAD-STORE-WHT")
    assert b.plans[0]["status"] == "void"
    assert "voided" in b.approve_plan(1)["error"]
    assert "fact_check" in b.checkout()["error"]


def test_preference_change_voids_the_plan(box):
    b = box()
    fill(b)
    b.fact_check(DRAFT)
    b.checkout()
    b.add_preference("Eggs must be cage-free")
    assert b.plans[0]["status"] == "void"
    assert [p["text"] for p in b.get_preferences()["preferences"]] == ["Eggs must be cage-free"]


def test_preferences_add_and_remove(box):
    b = box()
    pid = b.add_preference("  Paper towels   must be the name brand ")["preference"]["id"]
    assert b.preferences[0]["text"] == "Paper towels must be the name brand"
    b.remove_preference(pid)
    assert b.preferences == []
    assert "error" in b.remove_preference(pid)
    assert "error" in b.add_preference("   ")


def test_agent_cannot_approve():
    agent_tools = {t["name"] for t in TOOL_SPECS}
    assert "approve_plan" not in agent_tools
    assert not hasattr(mcp_server, "approve_plan")
    assert "get_preferences" in agent_tools


def test_store_refuses_tree_nut_items(box):
    b = box()
    r = b.add_to_cart("PB-STORE-16")
    assert "allergy" in r["error"].lower()
    assert b.store.cart.lines == []
    assert b.trail[-1]["status"] == "blocked"


def test_plan_held_under_delivery_minimum(box):
    b = box()
    b.add_to_cart("PB-SUNFLOWER-16")
    b.fact_check("Harvest Basket sells SunSeed Sunflower Seed Butter at $6.99.")
    r = b.checkout()
    assert "minimum" in r["error"]
    assert b.plans == []


def test_state_survives_reload(box, tmp_path):
    b = box()
    fill(b)
    b.add_preference("No name-brand milk")
    b.fact_check(DRAFT)
    b.checkout()
    b.save()
    again = ToolBox(tmp_path / "state.json")
    assert again.plans[0]["version"] == 1 and again.preferences[0]["text"] == "No name-brand milk"
    assert len(again.store.cart.lines) == len(BASKET)
    assert json.loads((tmp_path / "state.json").read_text())["cart_version"] == len(BASKET)

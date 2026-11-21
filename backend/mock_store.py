"""A tiny in-memory mock storefront for Harvest Basket Grocery.

This is deliberately NOT connected to any real payment, inventory or
delivery system. Senso provides the trusted context the agent reasons over
(catalog, household profile, order history, store policy); this module is
the "other integration" the FAQ says is responsible for actually creating a
cart or completing an order. Every action it returns is tagged
mode="simulated" so the trail never implies a real order happened.

As a defense-in-depth safety net (mirroring store_policy.md's allergy-flag
rule), add_to_cart also hard-blocks any product tagged with an allergen the
account has on file, regardless of what the agent decides - an automated
agent should never be the only thing standing between an allergen and a
household that flagged it.
"""

from dataclasses import dataclass, field
from typing import Optional

# tags: dietary/allergen markers. "tree_nut" products are hard-blocked below
# for any account with a tree_nut allergy flag, independent of agent behavior.
CATALOG = {
    "MILK-STORE-1G": {"sku": "MILK-STORE-1G", "name": "Harvest Basket Whole Milk (1 gal)", "price": 3.49, "unit": "1 gal", "brand_tier": "store", "tags": ["dairy"]},
    "MILK-NAME-1G": {"sku": "MILK-NAME-1G", "name": "Dairyvale Whole Milk (1 gal)", "price": 4.79, "unit": "1 gal", "brand_tier": "name", "tags": ["dairy"]},
    "MILK-OAT-64OZ": {"sku": "MILK-OAT-64OZ", "name": "Oatly Oat Milk (64 oz)", "price": 5.49, "unit": "64 oz", "brand_tier": "name", "tags": ["dairy_free", "vegan"]},
    "EGG-STORE-12": {"sku": "EGG-STORE-12", "name": "Harvest Basket Large Eggs (12-ct)", "price": 3.29, "unit": "12-ct", "brand_tier": "store", "tags": []},
    "EGG-CAGEFREE-12": {"sku": "EGG-CAGEFREE-12", "name": "Nestwell Cage-Free Eggs (12-ct)", "price": 5.49, "unit": "12-ct", "brand_tier": "name", "tags": ["cage_free"]},
    "BREAD-STORE-WHT": {"sku": "BREAD-STORE-WHT", "name": "Harvest Basket White Bread (20 oz)", "price": 2.49, "unit": "20 oz", "brand_tier": "store", "tags": ["gluten"]},
    "BREAD-NAME-WHL": {"sku": "BREAD-NAME-WHL", "name": "Golden Fields Whole Wheat Bread (20 oz)", "price": 4.29, "unit": "20 oz", "brand_tier": "name", "tags": ["gluten"]},
    "BREAD-GF-LOAF": {"sku": "BREAD-GF-LOAF", "name": "Harvest Basket Gluten-Free Bread (16 oz)", "price": 5.99, "unit": "16 oz", "brand_tier": "store", "tags": ["gluten_free"]},
    "PB-STORE-16": {"sku": "PB-STORE-16", "name": "Harvest Basket Peanut Butter (16 oz)", "price": 2.99, "unit": "16 oz", "brand_tier": "store", "tags": ["peanut", "tree_nut_facility"]},
    "PB-NAME-16": {"sku": "PB-NAME-16", "name": "NuttyCo Peanut Butter (16 oz)", "price": 4.49, "unit": "16 oz", "brand_tier": "name", "tags": ["peanut"]},
    "PB-SUNFLOWER-16": {"sku": "PB-SUNFLOWER-16", "name": "SunSeed Sunflower Seed Butter (16 oz)", "price": 6.99, "unit": "16 oz", "brand_tier": "name", "tags": ["peanut_free", "tree_nut_free"]},
    "PASTA-STORE-16": {"sku": "PASTA-STORE-16", "name": "Harvest Basket Spaghetti (16 oz)", "price": 1.29, "unit": "16 oz", "brand_tier": "store", "tags": ["gluten"]},
    "PASTA-NAME-16": {"sku": "PASTA-NAME-16", "name": "Romano's Spaghetti (16 oz)", "price": 2.49, "unit": "16 oz", "brand_tier": "name", "tags": ["gluten"]},
    "PASTA-GF-12": {"sku": "PASTA-GF-12", "name": "Harvest Basket Gluten-Free Penne (12 oz)", "price": 3.99, "unit": "12 oz", "brand_tier": "store", "tags": ["gluten_free"]},
    "RICE-STORE-5LB": {"sku": "RICE-STORE-5LB", "name": "Harvest Basket Long Grain White Rice (5 lb)", "price": 4.99, "unit": "5 lb", "brand_tier": "store", "tags": ["gluten_free"]},
    "OLIVEOIL-STORE-17OZ": {"sku": "OLIVEOIL-STORE-17OZ", "name": "Harvest Basket Olive Oil (17 oz)", "price": 7.99, "unit": "17 oz", "brand_tier": "store", "tags": []},
    "OLIVEOIL-NAME-17OZ": {"sku": "OLIVEOIL-NAME-17OZ", "name": "Terra Verde Extra Virgin Olive Oil (17 oz)", "price": 12.99, "unit": "17 oz", "brand_tier": "name", "tags": []},
    "BANANA-LB": {"sku": "BANANA-LB", "name": "Bananas", "price": 0.59, "unit": "per lb", "brand_tier": "n/a", "tags": []},
    "APPLE-GALA-LB": {"sku": "APPLE-GALA-LB", "name": "Gala Apples", "price": 1.79, "unit": "per lb", "brand_tier": "n/a", "tags": []},
    "PAPERTOWEL-STORE-6": {"sku": "PAPERTOWEL-STORE-6", "name": "Harvest Basket Paper Towels (6 rolls)", "price": 7.99, "unit": "6 rolls", "brand_tier": "store", "tags": []},
    "PAPERTOWEL-NAME-6": {"sku": "PAPERTOWEL-NAME-6", "name": "SoftGrip Paper Towels (6 rolls)", "price": 11.49, "unit": "6 rolls", "brand_tier": "name", "tags": []},
}

# Products tagged with any of these are hard-blocked for the account's allergy flags.
ALLERGEN_TAGS = {"tree_nut", "tree_nut_facility", "peanut"}


@dataclass
class CartLine:
    sku: str
    name: str
    price: float
    unit: str
    qty: float = 1
    no_substitutions: bool = False


@dataclass
class Cart:
    lines: list[CartLine] = field(default_factory=list)
    checked_out: bool = False
    order_id: Optional[str] = None

    @property
    def subtotal(self) -> float:
        return round(sum(line.price * line.qty for line in self.lines), 2)

    def to_dict(self) -> dict:
        return {
            "lines": [line.__dict__ for line in self.lines],
            "subtotal": self.subtotal,
            "checked_out": self.checked_out,
            "order_id": self.order_id,
            "mode": "simulated",
        }


class MockStore:
    """One cart per store instance; good enough for a single-session demo."""

    # Hardcoded to match household_profile.md's recorded allergy flag.
    ACCOUNT_ALLERGIES = {"tree_nut"}

    def __init__(self):
        self.cart = Cart()
        self._order_counter = 0

    def list_products(self, category: Optional[str] = None) -> dict:
        return {"products": list(CATALOG.values()), "mode": "simulated"}

    def get_product(self, sku: str) -> dict:
        product = CATALOG.get(sku.upper())
        if not product:
            return {"error": f"Unknown SKU '{sku}'", "mode": "simulated"}
        return {"product": product, "mode": "simulated"}

    def _blocked_by_allergy(self, product: dict) -> Optional[str]:
        for tag in product.get("tags", []):
            if tag in ALLERGEN_TAGS and (
                "tree_nut" in self.ACCOUNT_ALLERGIES and tag in {"tree_nut", "tree_nut_facility"}
            ):
                return tag
        return None

    def add_to_cart(self, sku: str, qty: float = 1, no_substitutions: bool = False) -> dict:
        product = CATALOG.get(sku.upper())
        if not product:
            return {"error": f"Unknown SKU '{sku}'", "mode": "simulated"}
        blocked_tag = self._blocked_by_allergy(product)
        if blocked_tag:
            return {
                "error": (
                    f"Blocked by account allergy flag: {product['name']} is tagged '{blocked_tag}', "
                    f"and this account has a tree_nut allergy flag on file. Per store policy, "
                    f"allergy-flagged items are never added or substituted onto this account."
                ),
                "mode": "simulated",
            }
        line = CartLine(sku=product["sku"], name=product["name"], price=product["price"], unit=product["unit"], qty=qty, no_substitutions=no_substitutions)
        self.cart.lines.append(line)
        return {"cart": self.cart.to_dict(), "mode": "simulated"}

    def checkout(self) -> dict:
        if not self.cart.lines:
            return {"error": "Cart is empty", "mode": "simulated"}
        if self.cart.subtotal < 35:
            return {"error": f"Order subtotal ${self.cart.subtotal:.2f} is below the $35 delivery minimum", "mode": "simulated"}
        self._order_counter += 1
        self.cart.checked_out = True
        self.cart.order_id = f"DEMO-ORDER-{self._order_counter:04d}"
        return {
            "order": self.cart.to_dict(),
            "mode": "simulated",
            "note": "This is a simulated checkout for a hackathon demo. No real payment or delivery occurred.",
        }

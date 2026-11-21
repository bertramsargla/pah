"""Turn recorded live sessions into frontend/examples.json for the shop app.

    python build_examples.py <recordings_dir>

A recording is <name>-<turn>.json: the /api/chat response after each turn.
"""

import datetime
import json
import pathlib
import re
import sys

from mock_store import CATALOG

FRONTEND = pathlib.Path(__file__).parent.parent / "frontend"
TITLES = {
    "restock": "Restock the usual order",
    "compare": "Compare peanut butter and olive oil",
    "unsafe": "Shopper asks for an unsafe item",
}


def catalog() -> list[dict]:
    rows, category = [], None
    for line in (pathlib.Path(__file__).parent / "context" / "products.md").read_text().splitlines():
        if line.startswith("## "):
            category = line[3:].strip()
            continue
        m = re.match(r"- SKU (\S+) — .+? — \$([\d.]+)(/lb)?(?: \(\$([\d.]+)/(\w+)\))?(?: — (.+))?$", line)
        if not m:
            continue
        sku, price, per_lb, ppu, unit, notes = m.groups()
        item = CATALOG[sku]
        blocked = any(t in ("tree_nut", "tree_nut_facility") for t in item["tags"])
        rows.append({
            "sku": sku, "name": item["name"], "category": category, "brand_tier": item["brand_tier"],
            "price": float(price), "price_per_unit": float(ppu) if ppu else (float(price) if per_lb else None),
            "per_unit": unit or ("lb" if per_lb else None), "notes": (notes or "").strip(),
            "allergy_status": "Blocked (tree nut)" if blocked else "Allowed",
        })
    return rows


def trim(step: dict) -> dict:
    s = {k: step[k] for k in ("step", "turn", "tool", "summary", "outcome", "status") if k in step}
    if step.get("citations"):
        s["citations"] = [{**{k: c.get(k) for k in ("document", "score", "rank", "content_id")}, "chunk_text": (c.get("chunk_text") or "")[:220]} for c in step["citations"]]
    if step.get("claims"):
        s["claims"] = [{**{k: c.get(k) for k in ("claim", "verdict", "rechecked")}, "evidence": " ".join((c.get("evidence") or "").split())[:200]} for c in step["claims"]]
        s["check_id"], s["recheck_id"] = step.get("check_id"), step.get("recheck_id")
    return s


def main(rec_dir: pathlib.Path):
    examples = []
    for name in TITLES:
        files = sorted(rec_dir.glob(f"{name}-*.json"), key=lambda p: int(p.stem.split("-")[-1]))
        if not files:
            continue
        turns = []
        for i, f in enumerate(files, start=1):
            d = json.loads(f.read_text())
            message = next(t["summary"] for t in d["trail"] if t["tool"] == "shopper" and t["turn"] == i)
            steps = [trim(t) for t in d["trail"] if t["turn"] == i and t["tool"] not in ("shopper", "reply")]
            turns.append({"message": message, "steps": steps, "reply": d["reply"], "cart": d["cart"]})
        recorded = datetime.datetime.fromtimestamp(files[0].stat().st_mtime, datetime.timezone.utc).strftime("%b %-d, %Y")
        examples.append({"id": name, "title": TITLES[name], "recorded": recorded, "turns": turns})
    out = FRONTEND / "examples.json"
    out.write_text(json.dumps({"catalog": catalog(), "examples": examples}, indent=1))
    print(f"wrote {out} with {len(examples)} examples")


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1]))

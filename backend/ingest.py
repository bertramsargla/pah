"""Push the fictional Trailhead Outfitters context into Senso.

Run once (or whenever context/*.md changes):
    python ingest.py

Requires SENSO_API_KEY in the environment (see .env.example).
Saves the resulting {filename: {id, kb_node_id}} mapping to context_ids.json
so the rest of the app / the audit trail can reference which doc a citation
came from.
"""

import json
import pathlib
import re

from dotenv import load_dotenv

from senso_client import SensoClient

load_dotenv()

CONTEXT_DIR = pathlib.Path(__file__).parent / "context"
OUT_FILE = pathlib.Path(__file__).parent / "context_ids.json"


BRAND_NAME = "Harvest Basket Grocery"
BRAND_DESCRIPTION = (
    "Harvest Basket is a fictional grocery retailer used for a hackathon demo. It sells "
    "groceries including dairy, eggs, bread, pantry staples, and household goods under its "
    "own store brand (Harvest Basket) as well as stocking name-brand alternatives."
)


def main():
    client = SensoClient()
    print("Checking API key...")
    who = client.whoami()
    print(f"  org: {who.get('name')} ({who.get('slug')}) free_tier={who.get('is_free_tier')}")

    print(f"Setting brand kit so fact-check can score claims about '{BRAND_NAME}'...")
    try:
        client.upsert_brand_kit(BRAND_NAME, BRAND_DESCRIPTION)
        print("  brand kit set.")
    except Exception as exc:
        print(f"  warning: could not set brand kit ({exc}); fact_check may return unscored claims.")

    mapping = {}
    for path in sorted(CONTEXT_DIR.glob("*.md")):
        title = path.stem.replace("_", " ").title()
        text = path.read_text()
        print(f"Ingesting {path.name} as '{title}'...")
        try:
            doc = client.ingest_raw(title=title, text=text)
        except Exception as exc:  # duplicate text (409) etc.
            match = re.search(r"\{.*\}", str(exc))
            existing_id = json.loads(match.group(0)).get("existing_content_id") if match else None
            print(f"  already ingested (existing_content_id={existing_id})")
            if existing_id:
                mapping[path.name] = {"id": existing_id, "kb_node_id": None, "title": title, "note": "already existed"}
            continue
        print(f"  -> id={doc['id']} kb_node_id={doc['kb_node_id']} status={doc['processing_status']}")
        node = client.wait_for_processing(doc["kb_node_id"])
        print(f"  -> ready: {node['content']['processing_status']}")
        mapping[path.name] = {"id": doc["id"], "kb_node_id": doc["kb_node_id"], "title": title}

    OUT_FILE.write_text(json.dumps(mapping, indent=2))
    print(f"\nWrote {OUT_FILE} with {len(mapping)} documents.")
    client.close()


if __name__ == "__main__":
    main()

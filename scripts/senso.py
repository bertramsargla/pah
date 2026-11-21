#!/usr/bin/env python3
"""Look at what WangSwipe filed in Senso and try a search, from a terminal.

The key comes from SENSO_API_KEY in the environment or in the repo's .env file
(which git ignores). It is never printed.

  python3 scripts/senso.py status            # documents in the knowledge base and their processing status
  python3 scripts/senso.py search "what goes with black jeans?"

Each call may use Senso credits.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = "https://apiv2.senso.ai/api/v1/"


def api_key():
    key = os.environ.get("SENSO_API_KEY", "")
    env_file = os.path.join(os.path.dirname(__file__), "..", ".env")
    if not key and os.path.exists(env_file):
        for line in open(env_file):
            name, _, value = line.strip().partition("=")
            if name == "SENSO_API_KEY":
                key = value.strip().strip('"')
    if not key:
        sys.exit("Set SENSO_API_KEY (environment or .env).")
    return key


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    request.add_header("X-API-Key", api_key())
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    try:
        return status, json.loads(raw or b"null")
    except ValueError:
        return status, raw.decode(errors="replace")[:500]


def show(label, status, payload):
    print(f"== {label}: HTTP {status}")
    print(json.dumps(payload, indent=2)[:3000] if not isinstance(payload, str) else payload)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("status", "search"):
        sys.exit(__doc__)
    if sys.argv[1] == "status":
        show("GET org/kb/root", *call("GET", "org/kb/root"))
        show("GET org/kb/find?q=WangSwipe", *call("GET", "org/kb/find?q=WangSwipe"))
    else:
        query = " ".join(sys.argv[2:]) or "What goes with black jeans?"
        show("POST org/search/context", *call("POST", "org/search/context", {"query": query, "max_results": 4}))


if __name__ == "__main__":
    main()

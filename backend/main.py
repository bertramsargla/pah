"""FastAPI backend for the Harvest Basket shopping agent.

    uvicorn main:app --port 8000      then open http://localhost:8000

AGENT_BACKEND picks the agent: "claude-code" runs Claude Code headless on this
machine's Claude login (no API key), "api" calls the Claude API with
ANTHROPIC_API_KEY. Defaults to "api" when that key is set, else "claude-code".
One demo session per server process.
"""

import os
import pathlib
import threading
import uuid

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel

load_dotenv()

BACKEND = pathlib.Path(__file__).parent
FRONTEND = BACKEND.parent / "frontend" / "index.html"
SESSIONS = BACKEND / ".sessions"
AGENT_BACKEND = os.environ.get("AGENT_BACKEND") or ("api" if os.environ.get("ANTHROPIC_API_KEY") else "claude-code")

app = FastAPI(title="Harvest Basket Shopping Agent")
_lock = threading.Lock()
_agent = None


def new_agent():
    session_dir = SESSIONS / uuid.uuid4().hex[:12]
    if AGENT_BACKEND == "api":
        from agent import ShoppingAgent
        return ShoppingAgent(session_dir)
    from agent_claude_code import ClaudeCodeAgent
    return ClaudeCodeAgent(session_dir)


def get_agent():
    global _agent
    if _agent is None:
        _agent = new_agent()
    return _agent


class ChatRequest(BaseModel):
    message: str


@app.get("/")
def index():
    return FileResponse(FRONTEND)


@app.get("/shop", response_class=HTMLResponse)
def shop():
    head = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
            '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}'
            'body{margin:0}[hidden]{display:none!important}img{max-width:100%}</style></head><body>')
    return head + (FRONTEND.parent / "shop.html").read_text() + "</body></html>"


@app.get("/examples.json")
def examples():
    return FileResponse(FRONTEND.parent / "examples.json")


class AddRequest(BaseModel):
    sku: str
    qty: float = 1


@app.post("/api/cart/add")
def cart_add(req: AddRequest):
    if _lock.locked():
        raise HTTPException(409, "The assistant is updating your cart. Try again in a moment.")
    from tools import ToolBox
    box = ToolBox(get_agent().state_path)
    result = box.add_to_cart(req.sku, req.qty)
    box.trail[-1]["by"] = "shopper"
    box.save()
    if "error" in result:
        raise HTTPException(400, result["error"])
    return {"cart": box.store.cart.to_dict()}


class SetRequest(BaseModel):
    sku: str
    qty: float
    no_substitutions: bool = False


@app.post("/api/cart/set")
def cart_set(req: SetRequest):
    """Set one item's quantity (0 removes it) and substitution preference, as the shopper."""
    if _lock.locked():
        raise HTTPException(409, "The assistant is updating your cart. Try again in a moment.")
    from tools import ToolBox
    box = ToolBox(get_agent().state_path)
    start = len(box.trail)
    box.remove_from_cart(req.sku)
    result = box.add_to_cart(req.sku, req.qty, req.no_substitutions) if req.qty > 0 else {}
    for step in box.trail[start:]:
        step["by"] = "shopper"
    box.save()
    if "error" in result:
        raise HTTPException(400, result["error"])
    return {"cart": box.store.cart.to_dict(), "trail": box.trail}


@app.post("/api/chat")
def chat(req: ChatRequest):
    if not _lock.acquire(blocking=False):
        raise HTTPException(409, "The agent is still working on the last message.")
    try:
        return get_agent().run_turn(req.message)
    finally:
        _lock.release()


@app.get("/api/state")
def state():
    agent = get_agent()
    return {"agent": agent.name, "busy": _lock.locked(), **agent.state()}


@app.post("/api/reset")
def reset():
    global _agent
    if _lock.locked():
        raise HTTPException(409, "The agent is still working.")
    _agent = None
    return {"ok": True}

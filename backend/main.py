"""FastAPI backend for the Trailhead Outfitters shopping agent demo.

Run with:
    uvicorn main:app --reload --port 8000

A single shared ShoppingAgent instance keeps conversation + cart state for
the demo session (hackathon-simple; not for multi-user production use).
"""

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from agent import ShoppingAgent

load_dotenv()

app = FastAPI(title="Trailhead Outfitters Shopping Agent")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_agent: ShoppingAgent | None = None


def get_agent() -> ShoppingAgent:
    global _agent
    if _agent is None:
        _agent = ShoppingAgent()
    return _agent


class ChatRequest(BaseModel):
    message: str


class ResetResponse(BaseModel):
    ok: bool


@app.post("/api/chat")
def chat(req: ChatRequest):
    agent = get_agent()
    return agent.run_turn(req.message)


@app.post("/api/reset")
def reset() -> ResetResponse:
    global _agent
    _agent = None
    return ResetResponse(ok=True)


@app.get("/api/health")
def health():
    return {"ok": True}

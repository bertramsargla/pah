"""Agent backend that calls the Claude API directly with tool use.

Needs ANTHROPIC_API_KEY. Uses the same tools, prompt and state file as the
Claude Code backend (agent_claude_code.py), so both leave the same trail.
"""

import json
import os
import pathlib

from anthropic import Anthropic

from prompt import SYSTEM_PROMPT, TOOL_SPECS
from tools import ToolBox

MODEL = os.environ.get("AGENT_MODEL", "claude-opus-5-5")


class ShoppingAgent:
    name = "claude-api"

    def __init__(self, session_dir):
        self.dir = pathlib.Path(session_dir)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.state_path = self.dir / "state.json"
        self.client = Anthropic()
        self.messages: list[dict] = []

    def state(self) -> dict:
        return ToolBox(self.state_path).snapshot()

    def run_turn(self, message: str, max_steps: int = 30) -> dict:
        box = ToolBox(self.state_path)
        box.start_turn(message)
        box.save()
        self.messages.append({"role": "user", "content": message})
        reply = "The agent stopped before finishing. Try rephrasing."
        for _ in range(max_steps):
            response = self.client.messages.create(model=MODEL, max_tokens=4000, system=SYSTEM_PROMPT, tools=TOOL_SPECS, messages=self.messages)
            self.messages.append({"role": "assistant", "content": response.content})
            uses = [b for b in response.content if b.type == "tool_use"]
            if not uses:
                reply = "".join(b.text for b in response.content if b.type == "text")
                break
            results = []
            for block in uses:
                box = ToolBox(self.state_path)
                try:
                    result = getattr(box, block.name)(**block.input)
                except Exception as exc:
                    box.log(block.name, json.dumps(block.input)[:120], f"Error: {exc}"[:300], "error")
                    result = {"error": str(exc)}
                box.save()
                results.append({"type": "tool_result", "tool_use_id": block.id, "content": json.dumps(result, default=str)})
            self.messages.append({"role": "user", "content": results})
        box = ToolBox(self.state_path)
        box.end_turn(reply, agent=self.name)
        box.save()
        return {"reply": reply, "agent": self.name, **box.snapshot()}

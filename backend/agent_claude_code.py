"""Agent backend that uses Claude Code in headless mode as the agent.

Runs `claude -p` with every built-in tool turned off and only the shop's MCP
tools allowed, so the agent can search Senso, fact-check and use the cart,
and nothing else. Uses whatever Claude login the machine has, so no separate
API key is needed. Each shopper message is one `claude -p` call that resumes
the previous one.
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys

from prompt import SYSTEM_PROMPT, TOOL_SPECS
from tools import ToolBox

BACKEND = pathlib.Path(__file__).parent
ALLOWED = [f"mcp__shop__{t['name']}" for t in TOOL_SPECS]


class ClaudeCodeAgent:
    name = "claude-code"

    def __init__(self, session_dir):
        self.dir = pathlib.Path(session_dir)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.state_path = self.dir / "state.json"
        self.session_id = None
        env = {"SHOP_STATE": str(self.state_path), "SENSO_API_KEY": os.environ.get("SENSO_API_KEY", "proxy-injected")}
        (self.dir / "mcp.json").write_text(json.dumps({"mcpServers": {"shop": {
            "command": sys.executable, "args": [str(BACKEND / "mcp_server.py")], "env": env,
        }}}))

    def state(self) -> dict:
        return ToolBox(self.state_path).snapshot()

    def run_turn(self, message: str) -> dict:
        box = ToolBox(self.state_path)
        box.start_turn(message)
        box.save()

        cmd = [
            shutil.which("claude") or "claude", "-p", message,
            "--output-format", "json",
            "--system-prompt", SYSTEM_PROMPT,
            "--tools", "",
            "--mcp-config", str(self.dir / "mcp.json"), "--strict-mcp-config",
            "--allowedTools", *ALLOWED,
            "--max-turns", os.environ.get("AGENT_MAX_TURNS", "30"),
        ]
        if os.environ.get("AGENT_MODEL"):
            cmd += ["--model", os.environ["AGENT_MODEL"]]
        if self.session_id:
            cmd += ["--resume", self.session_id]

        # A fact-check plus its re-check can take two minutes; Claude Code's default MCP timeout is shorter.
        env = {**os.environ, "MCP_TOOL_TIMEOUT": os.environ.get("MCP_TOOL_TIMEOUT", "300000")}
        proc = subprocess.run(cmd, cwd=self.dir, env=env, capture_output=True, text=True, timeout=900)
        try:
            out = json.loads(proc.stdout)
        except json.JSONDecodeError:
            out = {"is_error": True, "result": (proc.stderr or proc.stdout or "No output from claude -p")[-2000:]}
        self.session_id = out.get("session_id", self.session_id)
        reply = out.get("result") or "The agent stopped without a reply."

        box = ToolBox(self.state_path)
        box.end_turn(reply, agent=self.name, cost_usd=out.get("total_cost_usd"), turns=out.get("num_turns"), error=bool(out.get("is_error")))
        box.save()
        return {"reply": reply, "agent": self.name, **box.snapshot()}

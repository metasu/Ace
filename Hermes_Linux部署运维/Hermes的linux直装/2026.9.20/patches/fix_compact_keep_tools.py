#!/usr/bin/env python3
"""Install compact_request.py and wire it into conversation_loop (idempotent).

The helper slims Xiaoyi-sized payloads but NEVER pops tools/tool_choice.
Re-run after a hermes-agent upgrade so the hook survives source replacement.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERMES_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes")
AGENT_DIR = HERMES_DIR / "hermes-agent"
SRC = Path(__file__).resolve().parent / "compact_request.py"
DST = AGENT_DIR / "agent" / "compact_request.py"
LOOP = AGENT_DIR / "agent" / "conversation_loop.py"

HOOK = """            _run_phase(build_api_request, agent, s)
            # Deploy-local: slim huge Xiaoyi payloads without dropping tools.
            from agent.compact_request import apply_compact_request
            apply_compact_request(agent, s.api_kwargs)
            if _run_phase(perform_api_call, agent, s).action == "break":
"""

HOOK_OLD = """            _run_phase(build_api_request, agent, s)
            if _run_phase(perform_api_call, agent, s).action == "break":
"""


def ready() -> bool:
    if not DST.is_file() or not LOOP.is_file():
        return False
    loop = LOOP.read_text(encoding="utf-8", errors="ignore")
    helper = DST.read_text(encoding="utf-8", errors="ignore")
    return (
        "apply_compact_request(agent, s.api_kwargs)" in loop
        and "Never removes" in helper
        and "tools" in helper
        and "tool_choice" in helper
    )


def main() -> int:
    if not AGENT_DIR.is_dir():
        print(f"SKIP: hermes-agent missing: {AGENT_DIR}")
        return 0
    if not SRC.is_file():
        print(f"ERROR: missing helper source {SRC}", file=sys.stderr)
        return 1
    DST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC, DST)
    if not LOOP.is_file():
        print(f"ERROR: missing {LOOP}", file=sys.stderr)
        return 1
    text = LOOP.read_text(encoding="utf-8")
    if "apply_compact_request(agent, s.api_kwargs)" not in text:
        if HOOK_OLD not in text:
            print("ERROR: conversation_loop.py hook site not found (upstream changed?)", file=sys.stderr)
            return 1
        LOOP.write_text(text.replace(HOOK_OLD, HOOK, 1), encoding="utf-8")
    if not ready():
        print("ERROR: compact-keep-tools patch applied but verification failed", file=sys.stderr)
        return 2
    print(f"OK: compact-keep-tools → {DST} + conversation_loop hook")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

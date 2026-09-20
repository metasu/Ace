#!/usr/bin/env python3
"""Make per-session toolset override ADDITIVE for MCP servers (idempotent).

Upstream hermes-webui treats a session's ``enabled_toolsets`` as the
COMPLETE toolset list: in ``api/streaming.py`` the per-session override
replaces the resolved CLI toolsets wholesale. The composer toolsets
dropdown only lists MCP servers, so checking e.g. "github" produces
``enabled_toolsets=["github"]`` and silently strips ``hermes-cli``
(terminal / file-edit tools) from the session — the agent then reports
it "cannot modify files".

Fix: when a session override is present, resolve effective toolsets as
base (non-MCP) toolsets ∪ override entries. MCP picks are added on top
of the always-on regular tools instead of replacing them. An override
that names only base toolsets (e.g. ``["hermes-cli"]``) still yields the
base-only set, so stripping MCPs remains possible.

Also updates the toolsets dropdown description (en + zh locales) so the
UI states the additive semantics.
"""
from __future__ import annotations

import sys
from pathlib import Path

WEBUI = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes/hermes-webui")
STREAMING = WEBUI / "api" / "streaming.py"
I18N = WEBUI / "static" / "i18n.js"

STREAMING_REPLACEMENTS = [
    (
        "                    if _override:\n"
        "                        _toolsets = _override\n",
        "                    if _override:\n"
        "                        # Deploy-local patch: the session override is\n"
        "                        # ADDITIVE for MCP servers — non-MCP (base)\n"
        "                        # toolsets from the active profile always stay\n"
        "                        # enabled, so picking MCPs in the composer can\n"
        "                        # never strip hermes-cli / regular tools.\n"
        "                        _mcp_names = set(((_cfg or {}).get('mcp_servers') or {}).keys())\n"
        "                        _base_ts = [t for t in _toolsets if t not in _mcp_names]\n"
        "                        _toolsets = _base_ts + [t for t in _override if t not in _base_ts]\n",
    ),
]

I18N_REPLACEMENTS = [
    (
        "session_toolsets_desc:'Use active profile defaults or choose a custom toolset list for this session',",
        "session_toolsets_desc:'Base tools always on; pick MCP toolsets to add for this session',",
    ),
    (
        "session_toolsets_desc: '使用当前配置档默认工具，或为此会话选择自定义工具集',",
        "session_toolsets_desc: '常规工具始终启用；勾选要为本会话追加的 MCP 工具集',",
    ),
]


def ready() -> bool:
    if not (STREAMING.is_file() and I18N.is_file()):
        return False
    s = STREAMING.read_text(encoding="utf-8", errors="ignore")
    i = I18N.read_text(encoding="utf-8", errors="ignore")
    return "_base_ts" in s and "Base tools always on" in i


def apply_replacements(text: str, pairs: list[tuple[str, str]], label: str) -> str:
    for old, new in pairs:
        if new in text:
            continue  # already patched
        if old not in text:
            raise RuntimeError(f"{label}: pattern not found (upstream changed?): {old!r}")
        text = text.replace(old, new, 1)
    return text


def main() -> int:
    if not WEBUI.is_dir():
        print(f"SKIP: webui dir missing: {WEBUI}")
        return 0
    if ready():
        print(f"OK: additive-toolsets fix already present in {WEBUI}")
        return 0
    for p in (STREAMING, I18N):
        if not p.is_file():
            print(f"ERROR: missing {p}", file=sys.stderr)
            return 1
    try:
        STREAMING.write_text(
            apply_replacements(STREAMING.read_text(encoding="utf-8"), STREAMING_REPLACEMENTS, "streaming.py"),
            encoding="utf-8",
        )
        I18N.write_text(
            apply_replacements(I18N.read_text(encoding="utf-8"), I18N_REPLACEMENTS, "i18n.js"),
            encoding="utf-8",
        )
    except RuntimeError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    if not ready():
        print("ERROR: patch applied but verification failed", file=sys.stderr)
        return 2
    print(f"OK: applied additive-toolsets fix → {WEBUI}/api/streaming.py + static/i18n.js")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

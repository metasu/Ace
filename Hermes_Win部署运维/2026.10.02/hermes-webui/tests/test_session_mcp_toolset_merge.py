"""Regression tests: MCP-only session toolset overrides stay additive.

Composer MCP checkboxes write ``session.enabled_toolsets = ["<server>", ...]``.
That list used to replace the resolved profile toolsets wholesale, so a
session scoped to e.g. ``["github"]`` lost every native toolset (terminal,
file, web, …) — only the MCP server's tools survived. The fix merges
MCP-only overrides on top of the profile defaults while keeping genuine
(non-MCP) restrictions unchanged.
"""

from __future__ import annotations

from pathlib import Path

from api.config import _merge_session_toolsets

REPO = Path(__file__).resolve().parents[1]
STREAMING_PY = (REPO / "api" / "streaming.py").read_text(encoding="utf-8")

BASE = ["terminal", "file", "web", "memory", "github", "slack"]
CFG = {
    "mcp_servers": {
        "github": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"]},
        "slack": {"command": "npx", "args": ["-y", "slack-mcp"]},
        "disabled-one": {"enabled": False, "command": "true"},
    }
}


def test_mcp_only_override_merges_with_profile_defaults():
    result = _merge_session_toolsets(BASE, ["github"], CFG)
    assert result == BASE  # github was already in defaults; nothing lost


def test_mcp_only_override_appends_server_absent_from_defaults():
    cfg = {"mcp_servers": {"github": {}, "extra-mcp": {}}}
    result = _merge_session_toolsets(["terminal", "web"], ["extra-mcp"], cfg)
    assert result == ["terminal", "web", "extra-mcp"]


def test_multiple_mcp_servers_merge():
    result = _merge_session_toolsets(["terminal"], ["github", "slack"], CFG)
    assert result == ["terminal", "github", "slack"]


def test_mcp_prefixed_spelling_counts_as_mcp_entry():
    result = _merge_session_toolsets(["terminal"], ["mcp-github"], CFG)
    assert result == ["terminal", "mcp-github"]


def test_disabled_mcp_server_still_counts_as_mcp_entry():
    # A globally-disabled server has no registered tools, but selecting it
    # must still be additive — not a silent restrict-to-nothing.
    result = _merge_session_toolsets(["terminal"], ["disabled-one"], CFG)
    assert result == ["terminal", "disabled-one"]


def test_native_toolset_override_still_restricts():
    result = _merge_session_toolsets(BASE, ["web"], CFG)
    assert result == ["web"]


def test_mixed_native_and_mcp_override_restricts():
    result = _merge_session_toolsets(BASE, ["web", "github"], CFG)
    assert result == ["web", "github"]


def test_unknown_name_forces_restriction_semantics():
    # A typo / unknown entry means the user is writing a custom allowlist —
    # never silently fall back to defaults.
    result = _merge_session_toolsets(BASE, ["github", "bogus"], CFG)
    assert result == ["github", "bogus"]


def test_streaming_applies_merge_helper_at_override_site():
    """Pin the call site: the streaming worker must route the per-session
    override through _merge_session_toolsets instead of assigning it
    verbatim, or MCP checkbox selections strip the native toolsets."""
    assert "_toolsets = _merge_session_toolsets(_toolsets, _override, _cfg)" in STREAMING_PY
    assert "_toolsets = _override" not in STREAMING_PY


def test_chip_shows_defaults_plus_mcp_when_catalog_matches():
    src = (REPO / "static" / "ui.js").read_text(encoding="utf-8")
    assert "defaults + " in src
    assert "mcpOnly" in src

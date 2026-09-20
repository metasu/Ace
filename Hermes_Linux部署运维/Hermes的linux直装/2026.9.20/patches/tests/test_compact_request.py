"""Compact helper: slim text, never strip tools. 7 cases including source guards."""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

HERMES = Path("/opt/hermes")
AGENT = HERMES / "hermes-agent"
sys.path.insert(0, str(AGENT))

from agent.compact_request import (  # noqa: E402
    apply_compact_request,
    compact_payload,
    group_message_pairs,
    slim_text,
    trim_history_preserving_pairs,
)

TOOLS = [
    {"type": "function", "function": {"name": "write_file", "parameters": {}}},
    {"type": "function", "function": {"name": "terminal", "parameters": {}}},
    {"type": "function", "function": {"name": "generate_image", "parameters": {}}},
]


def test_short_request_unchanged():
    payload = {
        "messages": [{"role": "user", "content": "hello"}],
        "tools": TOOLS,
        "tool_choice": "auto",
    }
    compact_payload(payload)
    assert payload["tools"] is TOOLS
    assert payload["tool_choice"] == "auto"
    assert payload["messages"][0]["content"] == "hello"


def test_never_pop_tools_when_forced_slim():
    payload = {
        "system": "S" * 20_000,
        "messages": [{"role": "user", "content": "write a file"}],
        "tools": TOOLS,
        "tool_choice": "auto",
    }
    compact_payload(payload, force=True)
    assert "tools" in payload
    assert payload["tools"] is TOOLS
    assert len(payload["tools"]) == 3
    assert payload["tool_choice"] == "auto"
    names = [t["function"]["name"] for t in payload["tools"]]
    assert "write_file" in names and "terminal" in names


def test_never_pop_tool_choice_only_payload():
    payload = {"tool_choice": {"type": "function", "function": {"name": "write_file"}}}
    compact_payload(payload, force=True)
    assert payload["tool_choice"]["function"]["name"] == "write_file"


def test_history_trim_keeps_assistant_tool_pairs():
    messages = [
        {"role": "system", "content": "sys"},
        {"role": "user", "content": "u1"},
        {"role": "assistant", "content": "", "tool_calls": [{"id": "c1"}]},
        {"role": "tool", "content": "r1", "tool_call_id": "c1"},
        {"role": "user", "content": "u2"},
        {"role": "assistant", "content": "done"},
    ]
    groups = group_message_pairs(messages)
    assert len(groups[2]) == 2
    assert groups[2][0]["role"] == "assistant"
    assert groups[2][1]["role"] == "tool"
    trimmed = trim_history_preserving_pairs(messages, max_chars=50, keep_groups=2)
    roles = [m["role"] for m in trimmed]
    if "tool" in roles:
        idx = roles.index("tool")
        assert roles[idx - 1] == "assistant"


def test_long_system_is_slimmed():
    long_sys = "ABCDEFGH" * 2000
    assert len(long_sys) > 8000
    payload = {
        "system": long_sys,
        "messages": [{"role": "user", "content": "hi"}],
        "tools": TOOLS,
    }
    compact_payload(payload, force=True)
    assert len(payload["system"]) < len(long_sys)
    assert "truncated for gateway size" in payload["system"]
    assert payload["tools"] is TOOLS


def test_image_intent_adds_hint_without_dropping_tools():
    payload = {
        "messages": [{"role": "user", "content": "帮我生图一只猫"}],
        "tools": TOOLS,
        "tool_choice": "auto",
    }
    compact_payload(payload, force=True)
    assert "generate_image" in str(payload["tools"])
    assert "write_file" in str(payload["tools"])
    blob = " ".join(m["content"] for m in payload["messages"] if isinstance(m.get("content"), str))
    assert "image MCP" in blob or "generate_image" in blob


def test_source_guard_must_not_pop_tools():
    helper = (AGENT / "agent" / "compact_request.py").read_text(encoding="utf-8")
    loop = (AGENT / "agent" / "conversation_loop.py").read_text(encoding="utf-8")
    assert "apply_compact_request(agent, s.api_kwargs)" in loop
    assert 'pop("tools"' not in helper
    assert "pop('tools'" not in helper
    assert "del payload[\"tools\"]" not in helper
    assert "Never removes" in helper or "never removes" in helper.lower()
    slimmed = slim_text("x" * 20, limit=10)
    assert len(slimmed) <= 20 + 40


def test_apply_compact_request_restores_tools_for_xiaoyi():
    agent = SimpleNamespace(
        provider="xiaoyi-gpt-6-astra",
        model="gpt-6-astra",
        base_url="https://xiaoyiapi.xyz/v1",
    )
    kwargs = {
        "messages": [{"role": "user", "content": "在 D 盘写 md"}],
        "tools": TOOLS,
        "tool_choice": "auto",
        "system": "short",
    }
    apply_compact_request(agent, kwargs)
    assert kwargs["tools"] is TOOLS
    assert kwargs["tool_choice"] == "auto"


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in tests:
        try:
            fn()
            print(f"PASS {fn.__name__}")
        except Exception as exc:
            failed += 1
            print(f"FAIL {fn.__name__}: {exc}")
    print(f"{len(tests) - failed}/{len(tests)} passed")
    raise SystemExit(failed)

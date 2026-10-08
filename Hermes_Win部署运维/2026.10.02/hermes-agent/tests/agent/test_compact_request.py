"""Compact request must slim text without stripping agent tools.

Regression: HERMES_COMPACT_REQUEST_PROVIDERS used to pop() every tool
except a SudoCX image schema. GPT-6 then answered in plain text and
looked like it could not write files.
"""

from __future__ import annotations

from pathlib import Path

from agent.compact_request import (
    apply_compact_api_kwargs,
    apply_compact_request_if_needed,
    detect_image_intent,
    provider_uses_compact_request,
)


def _tool(name: str) -> dict:
    return {"type": "function", "function": {"name": name, "parameters": {"type": "object"}}}


def _kwargs(messages, tools=None, **extra):
    payload = {"messages": messages, "model": "gpt-6-astra"}
    if tools is not None:
        payload["tools"] = tools
    payload.update(extra)
    return payload


def test_compact_preserves_file_and_mcp_tools():
    tools = [_tool("write_file"), _tool("terminal"), _tool("mcp__github__get_file_contents")]
    payload = _kwargs(
        [
            {"role": "system", "content": "SOUL.md " * 2000},
            {"role": "user", "content": "Write a report on D:\\"},
        ],
        tools=tools,
        tool_choice="auto",
        parallel_tool_calls=True,
    )
    apply_compact_api_kwargs(payload)
    names = [t["function"]["name"] for t in payload["tools"]]
    assert names == ["write_file", "terminal", "mcp__github__get_file_contents"]
    assert payload.get("tool_choice") == "auto"
    assert payload.get("parallel_tool_calls") is True
    assert payload["messages"][0]["role"] == "system"
    assert "truncated" in payload["messages"][0]["content"]
    assert payload["messages"][-1]["content"] == "Write a report on D:\\"


def test_compact_keeps_tool_loop_messages():
    messages = [
        {"role": "system", "content": "sys"},
        {"role": "user", "content": "old"},
    ]
    for i in range(20):
        messages.append({"role": "user", "content": f"u{i}"})
        messages.append({"role": "assistant", "content": f"a{i}"})
    messages.extend(
        [
            {"role": "user", "content": "edit D:\a.md"},
            {
                "role": "assistant",
                "content": "",
                "tool_calls": [{"id": "c1", "function": {"name": "write_file"}}],
            },
            {"role": "tool", "tool_call_id": "c1", "content": "wrote"},
        ]
    )
    payload = _kwargs(messages, tools=[_tool("write_file")])
    apply_compact_api_kwargs(payload, history_window=6)
    roles = [m["role"] for m in payload["messages"]]
    assert roles[0] == "system"
    assert "tool" in roles
    assert payload["messages"][-1]["role"] == "tool"
    # Must not start a tool result without its assistant tool_calls turn.
    for i, role in enumerate(roles):
        if role == "tool":
            assert roles[i - 1] in {"tool", "assistant"}


def test_compact_does_not_run_for_unlisted_provider(monkeypatch):
    monkeypatch.setenv("HERMES_COMPACT_REQUEST_PROVIDERS", "xiaoyi-gpt-6-astra")
    payload = _kwargs(
        [{"role": "user", "content": "hi"}],
        tools=[_tool("write_file")],
    )
    apply_compact_request_if_needed(payload, "atlascloud-grok-4.3")
    assert payload["messages"] == [{"role": "user", "content": "hi"}]


def test_provider_match_is_case_insensitive():
    assert provider_uses_compact_request(
        "Xiaoyi-GPT-6-Astra", "xiaoyi-gpt-6-astra,xiaoyi-claude-fable-5-1"
    )
    assert not provider_uses_compact_request("other", "xiaoyi-gpt-6-astra")


def test_small_payload_is_not_rewritten():
    messages = [
        {"role": "system", "content": "short soul"},
        {"role": "user", "content": "Write D:\report.md"},
    ]
    payload = _kwargs(messages, tools=[_tool("write_file")])
    apply_compact_api_kwargs(payload)
    assert payload["messages"] == messages
    assert payload["tools"][0]["function"]["name"] == "write_file"


def test_image_intent_keeps_all_tools_not_just_image():
    tools = [_tool("write_file"), _tool("mcp__xiaoyi_grok_image__generate_image")]
    payload = _kwargs(
        [{"role": "system", "content": "sys"}, {"role": "user", "content": "帮我生图"}],
        tools=tools,
    )
    apply_compact_api_kwargs(payload)
    names = [t["function"]["name"] for t in payload["tools"]]
    assert "write_file" in names
    assert "mcp__xiaoyi_grok_image__generate_image" in names
    assert detect_image_intent(payload["messages"]) is True


def test_conversation_loop_keeps_tools_on_compact_path():
    src = Path(__file__).resolve().parents[2].joinpath("agent", "conversation_loop.py").read_text(encoding="utf-8")
    assert "apply_compact_request_if_needed" in src
    assert 'api_kwargs.pop("tools", None)' not in src
    assert 'api_kwargs.pop("tool_choice", None)' not in src

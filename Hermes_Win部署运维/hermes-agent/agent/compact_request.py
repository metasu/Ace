"""Slim LLM request payloads for gateways that time out on huge prompts.

Historically ``HERMES_COMPACT_REQUEST_PROVIDERS`` replaced the Hermes system
prompt with a one-line stub and **dropped every tool** except a SudoCX image
schema. That made GPT-6 look like it "cannot edit files": the request never
carried ``write_file`` / ``terminal`` / MCP tools, so a successful Xiaoyi
response never fell through to a full-tools fallback.

Compact now only shrinks the *text* surface (oversized system prompt + long
history) and **always preserves tools**, including MCP. Tool-call sequences
are kept intact so the model still sees tool results on the next API call.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Iterable

logger = logging.getLogger(__name__)

_IMAGE_INTENT_TERMS = (
    "sudocx-image",
    "generate_image",
    "generate image",
    "image generation",
    "draw ",
    "create image",
    "画",
    "绘制",
    "生图",
    "生成图片",
)

# Keep enough recent turns for a tool loop without re-sending the whole
# compressed session. 24 mixed-role messages is roughly the old "20 user
# messages" budget once assistant/tool pairs are counted.
_DEFAULT_HISTORY_WINDOW = 24
_SYSTEM_CHAR_BUDGET = 8000
_SYSTEM_KEEP_CHARS = 6000

_IMAGE_HINT = (
    "When the user requests an image, call the available image generation tool."
)


def compact_provider_names(raw: str | None = None) -> set[str]:
    source = raw if raw is not None else os.getenv("HERMES_COMPACT_REQUEST_PROVIDERS", "")
    return {item.strip().casefold() for item in str(source or "").split(",") if item.strip()}


def provider_uses_compact_request(provider: str | None, raw: str | None = None) -> bool:
    name = str(provider or "").strip().casefold()
    return bool(name) and name in compact_provider_names(raw)


def _message_text(message: Any) -> str:
    if not isinstance(message, dict):
        return ""
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                parts.append(str(item.get("text") or item.get("content") or ""))
        return "\n".join(parts)
    return str(content or "")


def detect_image_intent(messages: Iterable[Any] | None) -> bool:
    recent = []
    for message in list(messages or [])[-6:]:
        if str((message or {}).get("role") or "").casefold() != "user":
            continue
        recent.append(_message_text(message).casefold())
    blob = "\n".join(recent)
    return any(term in blob for term in _IMAGE_INTENT_TERMS)


def _is_image_tool(tool: Any) -> bool:
    if not isinstance(tool, dict):
        return False
    name = str((tool.get("function") or {}).get("name") or tool.get("name") or "").casefold()
    return "sudocx_image" in name or name.endswith("generate_image")


def _maybe_add_image_hint(content: Any) -> Any:
    if not isinstance(content, str) or _IMAGE_HINT in content:
        return content
    return content.rstrip() + "\n" + _IMAGE_HINT


def _trim_history_keep_tool_sequences(messages: list, max_messages: int) -> list:
    """Keep the newest ``max_messages`` entries without splitting a tool loop."""
    if max_messages <= 0 or len(messages) <= max_messages:
        return list(messages)
    start = len(messages) - max_messages
    while start > 0:
        head = messages[start]
        if not isinstance(head, dict):
            break
        role = str(head.get("role") or "").casefold()
        if role == "tool":
            start -= 1
            continue
        prev = messages[start - 1] if start > 0 else None
        if (
            role == "assistant"
            and head.get("tool_calls")
            and isinstance(prev, dict)
            and str(prev.get("role") or "").casefold() == "user"
        ):
            start -= 1
            continue
        break
    return list(messages[start:])


def _compact_system_content(content: Any) -> Any:
    if not isinstance(content, str):
        return content
    if len(content) <= _SYSTEM_CHAR_BUDGET:
        return content
    kept = content[:_SYSTEM_KEEP_CHARS].rstrip()
    return (
        kept
        + "\n\n[system prompt truncated for provider payload limits; tools remain fully available]"
    )


def apply_compact_api_kwargs(api_kwargs: dict, *, history_window: int = _DEFAULT_HISTORY_WINDOW) -> dict:
    """Mutate ``api_kwargs`` in place: shrink text, keep tools."""
    if not isinstance(api_kwargs, dict):
        return api_kwargs

    messages = api_kwargs.get("messages")
    if not isinstance(messages, list):
        messages = []

    image_intent = detect_image_intent(messages)
    original_tools = list(api_kwargs.get("tools") or [])
    systems = [m for m in messages if isinstance(m, dict) and str(m.get("role") or "").casefold() == "system"]
    rest = [m for m in messages if not (isinstance(m, dict) and str(m.get("role") or "").casefold() == "system")]
    system_content = systems[0].get("content") if systems else None
    already_small = (
        (not isinstance(system_content, str) or len(system_content) <= _SYSTEM_CHAR_BUDGET)
        and len(rest) <= history_window
    )

    if original_tools:
        api_kwargs["tools"] = original_tools

    if already_small:
        if image_intent and systems and any(_is_image_tool(t) for t in original_tools):
            system_msg = dict(systems[0])
            system_msg["content"] = _maybe_add_image_hint(system_msg.get("content"))
            api_kwargs["messages"] = [system_msg, *rest]
        return api_kwargs

    rest = _trim_history_keep_tool_sequences(rest, history_window)
    if systems:
        system_msg = dict(systems[0])
        system_msg["content"] = _compact_system_content(system_msg.get("content"))
        if image_intent and any(_is_image_tool(t) for t in original_tools):
            system_msg["content"] = _maybe_add_image_hint(system_msg.get("content"))
        compacted = [system_msg, *rest]
    else:
        compacted = rest or list(messages[-history_window:] or messages)

    api_kwargs["messages"] = compacted
    logger.debug(
        "compact request: messages=%d tools=%d image_intent=%s",
        len(compacted),
        len(original_tools),
        image_intent,
    )
    return api_kwargs


def apply_compact_request_if_needed(api_kwargs: dict, provider: str | None) -> dict:
    if provider_uses_compact_request(provider):
        return apply_compact_api_kwargs(api_kwargs)
    return api_kwargs

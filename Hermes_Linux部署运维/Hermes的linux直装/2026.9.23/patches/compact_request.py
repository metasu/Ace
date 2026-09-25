"""Gateway-size slimming that NEVER strips tools.

Xiaoyi (and similar) gateways can time out on huge system prompts. An earlier
deploy-local compact path dropped ``tools`` / ``tool_choice`` (keeping only an
image-gen stub) and collapsed history to user messages. GPT-6 then never saw
``write_file`` / ``terminal`` / MCP and could only reply with prose.

This helper:

- always keeps ``tools`` and ``tool_choice``
- only slims system text / history when they exceed thresholds
- sends short requests unchanged
- never splits assistant/tool pairs when trimming history
- may add an image-gen *hint*; it does not delete other tools

Text slimming is limited to providers in ``HERMES_COMPACT_REQUEST_PROVIDERS``
(xiaoyi / astra / opus by default) so other routes stay untouched.
"""

from __future__ import annotations

import os
import re
from typing import Any, Iterable, Mapping, MutableMapping, Sequence

DEFAULT_COMPACT_PROVIDERS: tuple[str, ...] = (
    "xiaoyi-gpt-6-astra",
    "xiaoyi-claude-opus-5-5",
    "xiaoyi",
    "gpt-6-astra",
    "claude-opus",
)

SYSTEM_SLIM_CHARS = 8_000
HISTORY_SLIM_CHARS = 24_000
HISTORY_KEEP_GROUPS = 12

_IMAGE_INTENT_RE = re.compile(
    r"(生图|画一张|画个|生成图片|文生图|图生图|generate an image|image generation|"
    r"txt2img|img2img|create an image)",
    re.IGNORECASE,
)

_IMAGE_HINT = (
    "If the user asked to generate or edit an image, use the image MCP tools "
    "(for example generate_image) in addition to write_file / terminal / MCP. "
    "Do not drop file or terminal tools."
)

_TOOLS_KEYS = ("tools", "tool_choice")


def compact_providers() -> set[str]:
    raw = os.environ.get("HERMES_COMPACT_REQUEST_PROVIDERS", "").strip()
    if raw:
        return {part.strip().lower() for part in raw.split(",") if part.strip()}
    return {name.lower() for name in DEFAULT_COMPACT_PROVIDERS}


def provider_needs_compact(
    provider: str | None = None,
    model: str | None = None,
    base_url: str | None = None,
) -> bool:
    names = compact_providers()
    blob = f"{provider or ''} {model or ''} {base_url or ''}".lower()
    if any(name in blob for name in names):
        return True
    return "xiaoyiapi" in (base_url or "").lower()


def _agent_needs_compact(agent: Any) -> bool:
    return provider_needs_compact(
        getattr(agent, "provider", None),
        getattr(agent, "model", None),
        getattr(agent, "base_url", None),
    )


def _as_text(content: Any) -> str:
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, Mapping):
                text = item.get("text")
                if isinstance(text, str):
                    parts.append(text)
        return "".join(parts)
    return str(content)


def _set_text(message: MutableMapping[str, Any], text: str) -> None:
    content = message.get("content")
    if isinstance(content, list) and content:
        replaced = False
        new_parts: list[Any] = []
        for item in content:
            if not replaced and isinstance(item, Mapping) and item.get("type", "text") == "text":
                new_parts.append({**item, "text": text})
                replaced = True
            elif not replaced and isinstance(item, str):
                new_parts.append(text)
                replaced = True
            else:
                new_parts.append(item)
        if not replaced:
            new_parts.append({"type": "text", "text": text})
        message["content"] = new_parts
        return
    message["content"] = text


def slim_text(text: str, limit: int = SYSTEM_SLIM_CHARS) -> str:
    if not text or len(text) <= limit:
        return text
    keep = max(1, limit // 2)
    return text[:keep] + "\n\n[...truncated for gateway size...]\n\n" + text[-keep:]


def _role(message: Mapping[str, Any] | Any) -> str:
    if isinstance(message, Mapping):
        return str(message.get("role") or "")
    return ""


def group_message_pairs(messages: Sequence[Mapping[str, Any]]) -> list[list[Mapping[str, Any]]]:
    """Group assistant+tool rows so history trim cannot split a tool loop."""
    groups: list[list[Mapping[str, Any]]] = []
    i = 0
    n = len(messages)
    while i < n:
        msg = messages[i]
        if _role(msg) == "assistant" and msg.get("tool_calls"):
            group: list[Mapping[str, Any]] = [msg]
            i += 1
            while i < n and _role(messages[i]) == "tool":
                group.append(messages[i])
                i += 1
            groups.append(group)
            continue
        groups.append([msg])
        i += 1
    return groups


def _group_chars(group: Sequence[Mapping[str, Any]]) -> int:
    return sum(len(_as_text(m.get("content"))) for m in group if isinstance(m, Mapping))


def _is_user_group(group: Sequence[Mapping[str, Any]]) -> bool:
    return any(_role(m) == "user" for m in group)


def trim_history_preserving_pairs(
    messages: Sequence[Mapping[str, Any]],
    *,
    max_chars: int = HISTORY_SLIM_CHARS,
    keep_groups: int = HISTORY_KEEP_GROUPS,
) -> list[Mapping[str, Any]]:
    if not messages:
        return []
    groups = group_message_pairs(list(messages))
    if not groups:
        return list(messages)

    leading: list[list[Mapping[str, Any]]] = []
    rest = groups
    while rest and _role(rest[0][0]) == "system":
        leading.append(rest[0])
        rest = rest[1:]

    if not rest:
        return [m for g in leading for m in g]

    kept_rev: list[list[Mapping[str, Any]]] = []
    chars = 0
    user_groups = 0
    for group in reversed(rest):
        extra = _group_chars(group)
        would_exceed = kept_rev and (chars + extra > max_chars) and len(kept_rev) >= keep_groups
        if would_exceed and user_groups >= 1:
            break
        kept_rev.append(group)
        chars += extra
        if _is_user_group(group):
            user_groups += 1
        if len(kept_rev) >= keep_groups and chars >= max_chars and user_groups >= 1:
            break

    kept = list(reversed(kept_rev))
    # If the oldest kept group is a dangling tool row, drop it rather than orphan it.
    while kept and all(_role(m) == "tool" for m in kept[0]):
        kept.pop(0)
    return [m for g in (*leading, *kept) for m in g]


def _iter_user_text(messages: Iterable[Mapping[str, Any]] | None) -> str:
    chunks: list[str] = []
    for msg in messages or ():
        if _role(msg) == "user":
            chunks.append(_as_text(msg.get("content")))
    return "\n".join(chunks)


def _maybe_image_hint(messages: list[MutableMapping[str, Any]] | None) -> None:
    if not messages:
        return
    if _IMAGE_HINT in " ".join(_as_text(m.get("content")) for m in messages):
        return
    if not _IMAGE_INTENT_RE.search(_iter_user_text(messages)):
        return
    last = messages[-1]
    if _role(last) == "user":
        existing = _as_text(last.get("content"))
        if _IMAGE_HINT not in existing:
            _set_text(last, existing.rstrip() + "\n\n" + _IMAGE_HINT)
        return
    messages.append({"role": "system", "content": _IMAGE_HINT})


def _needs_slim(system_text: str, messages: Sequence[Mapping[str, Any]] | None) -> bool:
    if len(system_text) > SYSTEM_SLIM_CHARS:
        return True
    body = 0
    count = 0
    for msg in messages or ():
        if _role(msg) == "system":
            if len(_as_text(msg.get("content"))) > SYSTEM_SLIM_CHARS:
                return True
            continue
        body += len(_as_text(msg.get("content")))
        count += 1
    return body > HISTORY_SLIM_CHARS or count > HISTORY_KEEP_GROUPS * 3


def _snapshot_tools(payload: Mapping[str, Any]) -> dict[str, Any]:
    snapped: dict[str, Any] = {}
    for key in _TOOLS_KEYS:
        if key in payload:
            snapped[key] = payload[key]
    return snapped


def _restore_tools(payload: MutableMapping[str, Any], snapped: Mapping[str, Any]) -> None:
    """Re-attach tools even if a future editor tries to pop them."""
    for key, value in snapped.items():
        payload[key] = value


def _slim_system_value(system: Any) -> Any:
    if isinstance(system, str):
        return slim_text(system)
    if isinstance(system, list):
        out = []
        for block in system:
            if isinstance(block, Mapping) and isinstance(block.get("text"), str):
                out.append({**block, "text": slim_text(block["text"])})
            else:
                out.append(block)
        return out
    return system


def compact_payload(payload: MutableMapping[str, Any], *, force: bool = False) -> MutableMapping[str, Any]:
    """Slim ``payload`` in place. Never removes ``tools`` / ``tool_choice``."""
    snapped = _snapshot_tools(payload)
    messages = payload.get("messages")
    msg_list: list[MutableMapping[str, Any]] = []
    if isinstance(messages, list):
        msg_list = [dict(m) if isinstance(m, Mapping) else m for m in messages]

    system_text = ""
    if isinstance(payload.get("system"), str):
        system_text = payload["system"]
    elif msg_list:
        system_text = "\n".join(
            _as_text(m.get("content")) for m in msg_list if isinstance(m, Mapping) and _role(m) == "system"
        )

    if force or _needs_slim(system_text, msg_list):
        if "system" in payload:
            payload["system"] = _slim_system_value(payload.get("system"))
        if msg_list:
            for msg in msg_list:
                if isinstance(msg, MutableMapping) and _role(msg) == "system":
                    _set_text(msg, slim_text(_as_text(msg.get("content"))))
            msg_list = [
                dict(m) if isinstance(m, Mapping) else m
                for m in trim_history_preserving_pairs(msg_list)
            ]
            payload["messages"] = msg_list

    if isinstance(payload.get("messages"), list):
        _maybe_image_hint(payload["messages"])

    _restore_tools(payload, snapped)
    return payload


def apply_compact_request(agent: Any, api_kwargs: MutableMapping[str, Any] | None) -> MutableMapping[str, Any] | None:
    """Entry used by ``conversation_loop``. Short / non-xiaoyi requests pass through."""
    if not isinstance(api_kwargs, MutableMapping):
        return api_kwargs
    snapped = _snapshot_tools(api_kwargs)
    try:
        if _agent_needs_compact(agent):
            compact_payload(api_kwargs)
    finally:
        _restore_tools(api_kwargs, snapped)
    return api_kwargs

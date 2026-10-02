"""Maintain Windows Hermes provider failover without changing model catalogs.

The script preserves the existing YAML text and only updates:
- agent.api_max_retries
- the top-level fallback_providers block

Provider definitions and their models mappings are never added, removed, or
rewritten. Fallback entries are generated only for providers that already exist.
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

import yaml


FALLBACK_CANDIDATES = (
    ("atlascloud", "xai/grok-4.3"),
    ("atlascloud", "xai/grok-4.6"),
    ("atlascloud", "openai/gpt-6-sol-codex"),
    ("kuaipao", "gpt-6.1-sol"),
)

_TOP_LEVEL_FALLBACK_RE = re.compile(
    r"^fallback_providers:\s*\n.*?(?=^[^\s#-][^:\n]*:\s*(?:#.*)?$|\Z)",
    re.MULTILINE | re.DOTALL,
)
_AGENT_BLOCK_RE = re.compile(
    r"^agent:\s*\n(?P<body>(?:^[ \t]+.*(?:\n|$)|^[ \t]*\n)*)",
    re.MULTILINE,
)


def _declared_model_ids(models_cfg: Any) -> list[str]:
    """Model ids declared in a provider's ``models`` allowlist.

    Accepts both config shapes: ``{"model-id": {...}}`` dicts and
    ``[{id: ...}]`` / ``["model-id"]`` lists.
    """
    ids: list[str] = []
    if isinstance(models_cfg, dict):
        ids = [str(k).strip() for k in models_cfg]
    elif isinstance(models_cfg, list):
        for item in models_cfg:
            if isinstance(item, dict):
                mid = item.get("id") or item.get("model") or item.get("name")
            else:
                mid = item
            if mid:
                ids.append(str(mid).strip())
    elif isinstance(models_cfg, str) and models_cfg.strip():
        ids.append(models_cfg.strip())
    return [i for i in ids if i]


def _fallback_model(provider_name: str, provider: dict[str, Any], candidate_model: str) -> str | None:
    """Resolve a target without mutating the provider's model catalog."""
    declared = _declared_model_ids(provider.get("models"))
    if candidate_model and candidate_model in declared:
        return candidate_model

    explicit = str(provider.get("model") or "").strip()
    if explicit:
        return explicit

    if declared:
        return declared[0]
    return candidate_model or None


def _build_fallback_chain(config: dict[str, Any]) -> list[dict[str, str]]:
    model_config = config.get("model")
    primary = str(model_config.get("provider") or "").strip() if isinstance(model_config, dict) else ""
    primary_model = str(model_config.get("default") or "").strip() if isinstance(model_config, dict) else ""
    providers = config.get("providers")
    if not isinstance(providers, dict):
        return []

    chain: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for candidate_name, candidate_model in FALLBACK_CANDIDATES:
        provider = providers.get(candidate_name)
        if not isinstance(provider, dict):
            continue
        model = _fallback_model(candidate_name, provider, candidate_model)
        if not model:
            continue
        # Keep same-provider protection models, but never duplicate the exact
        # active provider/model pair. Dedup is per (provider, model) so a
        # multi-model provider can contribute several chain entries.
        if (
            (candidate_name, model) in seen
            or (candidate_name == primary and model == primary_model)
        ):
            continue
        entry = {"provider": candidate_name, "model": model}
        key_env = str(provider.get("key_env") or "").strip()
        if key_env:
            entry["key_env"] = key_env
        base_url = str(provider.get("base_url") or "").strip()
        if base_url:
            entry["base_url"] = base_url
        chain.append(entry)
        seen.add((candidate_name, model))
    return chain


def _set_api_retries(text: str) -> str:
    """Keep one primary retry so the fallback branch remains reachable."""
    match = _AGENT_BLOCK_RE.search(text)
    if not match:
        insertion = "agent:\n  api_max_retries: 1\n"
        fallback_match = _TOP_LEVEL_FALLBACK_RE.search(text)
        position = fallback_match.start() if fallback_match else len(text.rstrip())
        prefix = text[:position].rstrip() + "\n"
        suffix = text[position:].lstrip("\n")
        return prefix + insertion + ("\n" + suffix if suffix else "")

    body = match.group("body")
    retry_re = re.compile(r"^  api_max_retries:.*$", re.MULTILINE)
    if retry_re.search(body):
        new_body = retry_re.sub("  api_max_retries: 1", body, count=1)
    else:
        new_body = "  api_max_retries: 1\n" + body
    return text[: match.start("body")] + new_body + text[match.end("body") :]


def _set_fallback_block(text: str, chain: list[dict[str, str]]) -> str:
    block = yaml.safe_dump(
        {"fallback_providers": chain},
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
    )
    if _TOP_LEVEL_FALLBACK_RE.search(text):
        return _TOP_LEVEL_FALLBACK_RE.sub(block + "\n", text, count=1)

    terminal_match = re.search(r"^terminal:\s*$", text, re.MULTILINE)
    position = terminal_match.start() if terminal_match else len(text.rstrip())
    prefix = text[:position].rstrip() + "\n\n"
    suffix = text[position:].lstrip("\n")
    return prefix + block + ("\n" + suffix if suffix else "")


def _atomic_write(path: Path, text: str) -> None:
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        os.replace(temp_name, path)
    except BaseException:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise


def configure(config_path: Path) -> bool:
    original = config_path.read_text(encoding="utf-8")
    config = yaml.safe_load(original) or {}
    if not isinstance(config, dict):
        raise ValueError("config.yaml root must be a mapping")

    chain = _build_fallback_chain(config)
    updated = _set_fallback_block(_set_api_retries(original), chain)

    parsed = yaml.safe_load(updated) or {}
    if parsed.get("fallback_providers") != chain:
        raise ValueError("fallback_providers verification failed")
    if (parsed.get("agent") or {}).get("api_max_retries") != 1:
        raise ValueError("agent.api_max_retries verification failed")

    changed = updated != original
    if changed:
        _atomic_write(config_path, updated)

    primary = (parsed.get("model") or {}).get("provider", "?")
    summary = " -> ".join(f"{item['provider']}/{item['model']}" for item in chain) or "(none)"
    print(f"[configure_failover] primary: {primary}")
    print(f"[configure_failover] fallback: {summary}")
    print(f"[configure_failover] {'updated' if changed else 'already current'}: {config_path}")
    return changed


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent
    config_path = root / "data" / "config.yaml"
    if not config_path.is_file():
        print(f"[configure_failover] config not found: {config_path}", file=sys.stderr)
        return 1
    try:
        configure(config_path)
    except Exception as exc:
        print(f"[configure_failover] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

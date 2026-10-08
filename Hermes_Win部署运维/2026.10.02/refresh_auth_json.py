"""Refresh auth.json from .env and config.yaml (Windows portable variant).

Mirrors the Linux 2026.8.17 refresh_auth_json.py but resolves paths against
the portable root directory instead of hardcoded /opt/hermes.
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone


def _root() -> pathlib.Path:
    return pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent


ROOT = _root()
ENV_PATH = ROOT / "data" / ".env"
AUTH_PATH = ROOT / "data" / "auth.json"
CONFIG_PATH = ROOT / "data" / "config.yaml"


def _load_env(path: pathlib.Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$", line)
        if m:
            env[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return env


def _resolve(val: str, env: dict[str, str]) -> str:
    if not val:
        return val

    def _repl(m: re.Match[str]) -> str:
        name = m.group(1) or m.group(2)
        return env.get(name, "")

    return re.sub(r"\$\{([A-Z0-9_]+)\}|\$([A-Z0-9_]+)", _repl, val)


def _cred(provider: str, label: str, key_var: str, base_url_var: str, default_base_url: str, env: dict[str, str]) -> dict:
    access_token = env.get(key_var, "") if key_var else ""
    if not access_token and key_var and key_var.startswith("HERMES_"):
        alt = key_var.replace("HERMES_", "").replace("_KEY", "_API_KEY")
        access_token = env.get(alt, "")
    return {
        "id": provider,
        "label": label,
        "auth_type": "api_key",
        "priority": 0,
        "source": f"env:{key_var}" if key_var else "config",
        "access_token": access_token,
        "base_url": _resolve(env.get(base_url_var, default_base_url), env),
        "request_count": 0,
        "last_status": None,
        "last_status_at": None,
        "last_error_code": None,
        "last_error_reason": None,
        "last_error_message": None,
        "last_error_reset_at": None,
    }


def _provider_cred(name: str, info: dict | None, env: dict[str, str]) -> dict | None:
    if not isinstance(info, dict):
        return None
    key_var = str(info.get("key_env") or "").strip()
    raw_key = str(info.get("api_key") or "").strip()
    if not key_var and raw_key:
        m = re.match(r"^\$\{([A-Z0-9_]+)\}$", raw_key)
        if m:
            key_var = m.group(1)
    base_url = str(info.get("base_url") or "").strip()
    if not base_url or (not key_var and not raw_key):
        return None
    base_var = ""
    m = re.match(r"^\$\{([A-Z0-9_]+)\}$", base_url)
    if m:
        base_var = m.group(1)
    result = _cred(name, name, key_var, base_var, _resolve(base_url, env), env)
    if not key_var and raw_key:
        result["access_token"] = raw_key
    return result if result.get("access_token") else None


def main() -> int:
    env = _load_env(ENV_PATH)

    cfg_providers: dict = {}
    try:
        import yaml
        cfg = yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))
        cfg_providers = cfg.get("providers", {}) if cfg else {}
    except Exception as exc:
        print(f"[warn] 读取 config.yaml 失败: {exc}", file=sys.stderr)

    credential_pool = {
        "anthropic": [_cred("newapi-anthropic", "ANTHROPIC_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "http://127.0.0.1:50006", env)],
        "gemini": [_cred("newapi-gemini", "GOOGLE_API_KEY", "GOOGLE_API_KEY", "GEMINI_BASE_URL", "http://127.0.0.1:50006/v1", env)],
        "openai": [_cred("openai-compatible", "OPENAI_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "", env)],
        "openrouter": [],
    }

    for name, info in cfg_providers.items():
        cred_info = _provider_cred(name, info, env)
        if cred_info:
            credential_pool.setdefault(f"custom:{name}", []).append(cred_info)

    data = {
        "version": 1,
        "providers": {},
        "credential_pool": credential_pool,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }

    AUTH_PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"✅ auth.json 已从 .env 刷新: {AUTH_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

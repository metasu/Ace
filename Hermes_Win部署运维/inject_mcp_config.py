"""Inject MCP server configuration into data/config.yaml.

Generates the entire mcp_servers YAML section with paths relative to
ROOT_DIR and API keys read from environment variables, then replaces
any existing mcp_servers section in config.yaml.

This keeps all MCP configuration OUT of config.yaml — it is generated
at startup by start.bat calling this script, so paths always match the
current drive letter and keys come from start.bat env vars.

Usage:
    python inject_mcp_config.py             # auto-detect root = script dir
    python inject_mcp_config.py F:\\hermes_ui  # explicit root
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def _env(name: str) -> str:
    return os.environ.get(name, "")


def generate_mcp_yaml(root: str) -> str:
    xiaoyi_grok_image_key = _env("XIAOYI_GROK_IMAGE_KEY")
    atlascloud_key = _env("MCP_ATLASCLOUD_KEY")
    atlascloud_url = _env("MCP_ATLASCLOUD_API_URL") or "https://api.atlascloud.ai"
    out = f"{root}\\output"

    return (
        "mcp_servers:\n"
        "  xiaoyi-grok-image:\n"
        "    command: node\n"
        "    args:\n"
        f"      - {root}\\mcp\\xiaoyi-grok-image\\build\\index.js\n"
        "    timeout: 660\n"
        "    env:\n"
        f"      API_KEY: {xiaoyi_grok_image_key}\n"
        "      API_URL: https://xiaoyiapi.xyz/v1\n"
        "      DEFAULT_IMAGE_MODEL: grok-imagine-image\n"
        "      DEFAULT_IMAGE_SIZE: 2048x2048\n"
        f"      DEFAULT_OUTPUT_PATH: {out}\n"
        "      REQUEST_TIMEOUT: '600000'\n"
        "  atlascloud-seedream-v5.0-pro:\n"
        "    command: node\n"
        "    args:\n"
        f"      - {root}\\mcp\\atlascloud-seedream-v5-pro\\build\\index.js\n"
        "    timeout: 660\n"
        "    env:\n"
        f"      API_KEY: {atlascloud_key}\n"
        f"      API_URL: {atlascloud_url}\n"
        "      DEFAULT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/text-to-image\n"
        f"      DEFAULT_OUTPUT_PATH: {out}\n"
        "      REQUEST_TIMEOUT: '600000'\n"
        "  atlascloud-seedream-v5.0-pro-edit:\n"
        "    command: node\n"
        "    args:\n"
        f"      - {root}\\mcp\\atlascloud-seedream-edit\\build\\index.js\n"
        "    timeout: 660\n"
        "    env:\n"
        f"      API_KEY: {atlascloud_key}\n"
        f"      API_URL: {atlascloud_url}\n"
        "      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-pro/edit\n"
        f"      DEFAULT_OUTPUT_PATH: {out}\n"
        "      REQUEST_TIMEOUT: '600000'\n"
        "  atlascloud-seedream-v5.0-lite-sequential:\n"
        "    command: node\n"
        "    args:\n"
        f"      - {root}\\mcp\\atlascloud-seedream-edit-sequential\\build\\index.js\n"
        "    timeout: 660\n"
        "    env:\n"
        f"      API_KEY: {atlascloud_key}\n"
        f"      API_URL: {atlascloud_url}\n"
        "      DEFAULT_EDIT_IMAGE_MODEL: bytedance/seedream-v5.0-lite/edit-sequential\n"
        f"      DEFAULT_OUTPUT_PATH: {out}\n"
        "      REQUEST_TIMEOUT: '600000'\n"
        "  atlascloud-wan-edit:\n"
        "    command: node\n"
        "    args:\n"
        f"      - {root}\\mcp\\atlascloud-wan-edit\\build\\index.js\n"
        "    timeout: 660\n"
        "    env:\n"
        f"      API_KEY: {atlascloud_key}\n"
        f"      API_URL: {atlascloud_url}\n"
        "      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7/image-edit\n"
        f"      DEFAULT_OUTPUT_PATH: {out}\n"
        "      REQUEST_TIMEOUT: '600000'\n"
        "  atlascloud-wan-edit-pro:\n"
        "    command: node\n"
        "    args:\n"
        f"      - {root}\\mcp\\atlascloud-wan-edit-pro\\build\\index.js\n"
        "    timeout: 660\n"
        "    env:\n"
        f"      API_KEY: {atlascloud_key}\n"
        f"      API_URL: {atlascloud_url}\n"
        "      DEFAULT_EDIT_IMAGE_MODEL: alibaba/wan-2.7-pro/image-edit\n"
        f"      DEFAULT_OUTPUT_PATH: {out}\n"
        "      REQUEST_TIMEOUT: '600000'\n"
        "  github:\n"
        "    command: npx\n"
        "    args:\n"
        "      - -y\n"
        "      - '@modelcontextprotocol/server-github'\n"
        "    timeout: 60\n"
        "    env:\n"
        f"      GITHUB_PERSONAL_ACCESS_TOKEN: {_env('GITHUB_PERSONAL_ACCESS_TOKEN')}\n"
        "\n"
    )


# Match from "mcp_servers:" at column 0 to the next non-whitespace line at column 0
_MCP_BLOCK_RE = re.compile(
    r"^mcp_servers:\n.*?(?=^[^\s]|\Z)",
    re.MULTILINE | re.DOTALL,
)


def inject_mcp_config(config_path: Path, root: str) -> bool:
    text = config_path.read_text(encoding="utf-8")
    new_block = generate_mcp_yaml(root)

    if _MCP_BLOCK_RE.search(text):
        text = _MCP_BLOCK_RE.sub(lambda m: new_block, text)
    else:
        text = text.rstrip("\n") + "\n\n" + new_block

    config_path.write_text(text, encoding="utf-8", newline="\n")
    return True


def main() -> int:
    if len(sys.argv) > 1:
        root = str(Path(sys.argv[1]).resolve()).rstrip("\\")
    else:
        root = str(Path(__file__).resolve().parent).rstrip("\\")

    config = Path(root) / "data" / "config.yaml"
    if not config.is_file():
        print(f"[inject_mcp_config] config not found: {config}", file=sys.stderr)
        return 1

    inject_mcp_config(config, root)
    print(f"[inject_mcp_config] OK - mcp_servers injected into {config}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

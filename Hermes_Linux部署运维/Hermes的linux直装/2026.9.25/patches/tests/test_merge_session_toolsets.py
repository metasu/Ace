"""Session MCP toolsets are additive. 10 cases around _merge_session_toolsets."""
from __future__ import annotations

import ast
from pathlib import Path

STREAMING = Path("/opt/hermes/hermes-webui/api/streaming.py")
UI = Path("/opt/hermes/hermes-webui/static/ui.js")
I18N = Path("/opt/hermes/hermes-webui/static/i18n.js")


def _load_merge():
    src = STREAMING.read_text(encoding="utf-8")
    tree = ast.parse(src)
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "_merge_session_toolsets":
            ns: dict = {}
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(STREAMING), "exec"), ns)
            return ns["_merge_session_toolsets"]
    raise AssertionError("_merge_session_toolsets missing from streaming.py")


merge = _load_merge()
MCP = {"github", "xiaoyi-grok-image"}
BASE = ["hermes-cli", "github"]


def test_no_override_keeps_base():
    assert merge(BASE, None, MCP) == BASE


def test_empty_override_keeps_base():
    assert merge(BASE, [], MCP) == BASE


def test_mcp_only_override_adds_on_top_of_non_mcp_base():
    assert merge(BASE, ["github"], MCP) == ["hermes-cli", "github"]


def test_other_mcp_override_replaces_default_mcp_keeps_cli():
    assert merge(BASE, ["xiaoyi-grok-image"], MCP) == ["hermes-cli", "xiaoyi-grok-image"]


def test_base_only_override_strips_mcp():
    assert merge(BASE, ["hermes-cli"], MCP) == ["hermes-cli"]


def test_cli_plus_mcp_override():
    assert merge(BASE, ["hermes-cli", "github"], MCP) == ["hermes-cli", "github"]


def test_does_not_duplicate():
    assert merge(["hermes-cli"], ["hermes-cli", "github"], MCP) == ["hermes-cli", "github"]


def test_empty_base_uses_override():
    assert merge([], ["github"], MCP) == ["github"]


def test_preserves_base_order_then_new_override():
    base = ["hermes-cli", "web", "file"]
    assert merge(base, ["github", "hermes-cli"], MCP) == ["hermes-cli", "web", "file", "github"]


def test_source_and_ui_additive_contract():
    streaming = STREAMING.read_text(encoding="utf-8")
    ui = UI.read_text(encoding="utf-8")
    i18n = I18N.read_text(encoding="utf-8")
    assert "def _merge_session_toolsets" in streaming
    assert "_toolsets = _override" not in streaming.split("if _override:")[1][:400]
    assert "defaults + " in ui
    assert "Checking MCP does not turn off terminal/file tools" in i18n
    assert "勾选 MCP 不会关掉终端/文件工具" in i18n


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

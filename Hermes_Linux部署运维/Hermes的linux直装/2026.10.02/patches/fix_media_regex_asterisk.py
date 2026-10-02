#!/usr/bin/env python3
"""Fix MEDIA:/file:// token regexes in hermes-webui static JS (idempotent).

The agent frequently emits generated-image references wrapped in markdown
bold, e.g. `**MEDIA:/opt/hermes/data/output/images/xxx.jpeg**`. Upstream's
`MEDIA:` and bare `file://` token regexes only exclude whitespace/`)`/`]`,
so the trailing `**` gets swallowed into the captured path, producing a
broken URL (`...jpeg**`) that 404s and falls back to a plain text link
instead of an inline <img>.

Fix: exclude `*` from the captured path in every MEDIA:/file:// regex in
static/ui.js (full-pipeline renderMd()) and static/messages.js (streaming
_smdMediaAwareAddText()), so markdown bold delimiters around a MEDIA: token
are left outside the captured reference.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

WEBUI = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes/hermes-webui")
UI = WEBUI / "static" / "ui.js"
MESSAGES = WEBUI / "static" / "messages.js"

# (old_regex_source, new_regex_source) pairs, applied as literal string
# replacements against the JS source (not compiled — these are JS regex
# literals embedded in the file text).
UI_REPLACEMENTS = [
    (
        r"s=s.replace(/MEDIA:([^\s\)\]]+)/g,(_,raw_ref)=>{",
        r"s=s.replace(/MEDIA:([^\s\)\]\*]+)/g,(_,raw_ref)=>{",
    ),
    (
        r"""s=s.replace(/(^|\s)(file:\/\/[^\s<>"')\]]+)/g,(_,lead,raw_ref)=>{""",
        r"""s=s.replace(/(^|\s)(file:\/\/[^\s<>"')\]\*]+)/g,(_,lead,raw_ref)=>{""",
    ),
]

MESSAGES_REPLACEMENTS = [
    (
        r"const m=/^MEDIA:([^\s\)\]]+)$/.exec(String(chunk));",
        r"const m=/^MEDIA:([^\s\)\]\*]+)$/.exec(String(chunk));",
    ),
    (
        r"const re=/MEDIA:([^\s\)\]]+)/g;",
        r"const re=/MEDIA:([^\s\)\]\*]+)/g;",
    ),
    (
        r"const tailMatch = /MEDIA:[^\s\)\]]*$/.exec(rest);",
        r"const tailMatch = /MEDIA:[^\s\)\]\*]*$/.exec(rest);",
    ),
]


def ready() -> bool:
    if not (UI.is_file() and MESSAGES.is_file()):
        return False
    u = UI.read_text(encoding="utf-8", errors="ignore")
    m = MESSAGES.read_text(encoding="utf-8", errors="ignore")
    return (
        r"MEDIA:([^\s\)\]\*]+)" in u
        and r"MEDIA:([^\s\)\]\*]+)" in m
        and r"MEDIA:[^\s\)\]\*]*$" in m
    )


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
        print(f"OK: MEDIA regex fix already present in {WEBUI}")
        return 0
    for p in (UI, MESSAGES):
        if not p.is_file():
            print(f"ERROR: missing {p}", file=sys.stderr)
            return 1
    UI.write_text(apply_replacements(UI.read_text(encoding="utf-8"), UI_REPLACEMENTS, "ui.js"), encoding="utf-8")
    MESSAGES.write_text(
        apply_replacements(MESSAGES.read_text(encoding="utf-8"), MESSAGES_REPLACEMENTS, "messages.js"),
        encoding="utf-8",
    )
    if not ready():
        print("ERROR: patch applied but verification failed", file=sys.stderr)
        return 2
    print(f"OK: applied MEDIA regex fix → {WEBUI}/static/{{ui,messages}}.js")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

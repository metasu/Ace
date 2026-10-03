#!/usr/bin/env python3
"""Fix mobile rendering of Qimen nine-palace ASCII grids in hermes-webui (idempotent).

The yinpanqimen skill delivers the nine-palace chart as a fixed-width ASCII
grid inside a fenced ```text code block (`+---+` borders, 【宫位】 labels,
神/星/门/天/引 rows). Under `@media(max-width:700px)` the WebUI forces every
`.msg-body pre` to `white-space:pre-wrap`, which wraps the border lines and
palace contents into unrelated rows and destroys the column alignment.

Fix: detect qimen grids in static/ui.js renderMd() and tag their <pre> with
`qimen-grid-block`; in static/style.css exempt that class from the mobile
pre-wrap override — keep `pre`, shrink font, allow horizontal touch pan.

Detector requires ALL of: a `+---+` border line, >=3 `|【宫位】` labels, and a
`|神 `/`|星 `/`|门 `/`|天 `/`|引 ` row — plain ASCII tables are not affected.
The row-label lookahead must be `(?:\\s|$)`, NOT `\\b` (JS \\b only sees ASCII
word chars, so a CJK label followed by whitespace never matches).
"""
from __future__ import annotations

import sys
from pathlib import Path

WEBUI = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes/hermes-webui")
UI = WEBUI / "static" / "ui.js"
CSS = WEBUI / "static" / "style.css"

DETECTOR_FN = """function _looksLikeQimenGridCode(code){
  const text=String(code||'');
  if(!/[+][-=]{3,}[+]/.test(text)) return false;
  const palaceLabels=(text.match(/\\|\\s*【[^】]+】/g)||[]).length;
  if(palaceLabels<3) return false;
  return /\\|\\s*(?:神|星|门|天|引)(?:\\s|$)/.test(text);
}

function renderMd(raw){"""

PRECLASS_OLD = "const preClass=/^(md|markdown|mdx)$/.test(lang)?' class=\"md-source-block\"':'';"
PRECLASS_NEW = "const preClass=/^(md|markdown|mdx)$/.test(lang)?' class=\"md-source-block\"':(_looksLikeQimenGridCode(code)?' class=\"qimen-grid-block\"':'');"

CSS_ANCHOR = "    .diff-block .diff-line{white-space:pre-wrap !important;overflow-wrap:anywhere !important;word-break:break-word !important;}"
CSS_BLOCK = """    /* Qimen nine-palace grids are intentional fixed-width ASCII layouts. Keep
       their columns aligned on phones and let the user pan horizontally instead
       of wrapping border lines and palace contents into unrelated rows. */
    .msg-body pre.qimen-grid-block{
      max-width:100%;
      overflow-x:auto !important;
      overflow-y:hidden;
      white-space:pre !important;
      overflow-wrap:normal !important;
      word-break:normal !important;
      font-family:var(--font-mono,ui-monospace),monospace !important;
      /* Shrink the complete grid on phones before enabling pan. */
      font-size:clamp(8px,2.2vw,var(--message-pre-code-font-size)) !important;
      line-height:1.35 !important;
      -webkit-overflow-scrolling:touch;
      overscroll-behavior-inline:contain;
      touch-action:pan-x pan-y;
    }
    .msg-body pre.qimen-grid-block code{
      display:block;
      width:max-content;
      min-width:100%;
      font-size:inherit !important;
      line-height:inherit !important;
      white-space:pre !important;
      overflow-wrap:normal !important;
      word-break:normal !important;
    }
    .msg-body pre.qimen-grid-block code .token{
      white-space:pre !important;
      overflow-wrap:normal !important;
      word-break:normal !important;
    }"""


def ready() -> bool:
    if not (UI.is_file() and CSS.is_file()):
        return False
    u = UI.read_text(encoding="utf-8", errors="ignore")
    c = CSS.read_text(encoding="utf-8", errors="ignore")
    return (
        "function _looksLikeQimenGridCode(" in u
        and "' class=\"qimen-grid-block\"'" in u
        and PRECLASS_OLD not in u  # every preClass site patched (renderMd + user fenced blocks)
        and ".msg-body pre.qimen-grid-block{" in c
    )


def main() -> int:
    if not WEBUI.is_dir():
        print(f"SKIP: webui dir missing: {WEBUI}")
        return 0
    if ready():
        print(f"OK: qimen mobile fix already present in {WEBUI}")
        return 0
    for p in (UI, CSS):
        if not p.is_file():
            print(f"ERROR: missing {p}", file=sys.stderr)
            return 1

    u = UI.read_text(encoding="utf-8")
    if "function _looksLikeQimenGridCode(" not in u:
        if "function renderMd(raw){" not in u:
            print("ERROR: ui.js: `function renderMd(raw){` not found (upstream changed?)", file=sys.stderr)
            return 1
        u = u.replace("function renderMd(raw){", DETECTOR_FN, 1)
    if PRECLASS_OLD in u:
        # Same pattern appears in both renderMd() (assistant path) and
        # _renderUserFencedBlocks() (user message path) — patch every
        # occurrence, the grid breaks identically in either renderer.
        u = u.replace(PRECLASS_OLD, PRECLASS_NEW)
        if PRECLASS_OLD in u:
            print("ERROR: ui.js: preClass replacement incomplete", file=sys.stderr)
            return 1
    elif "' class=\"qimen-grid-block\"'" not in u:
        print("ERROR: ui.js: preClass line not found (upstream changed?)", file=sys.stderr)
        return 1

    c = CSS.read_text(encoding="utf-8")
    if ".msg-body pre.qimen-grid-block{" not in c:
        if CSS_ANCHOR not in c:
            print("ERROR: style.css: mobile diff-line pre-wrap anchor not found (upstream changed?)", file=sys.stderr)
            return 1
        c = c.replace(CSS_ANCHOR, CSS_ANCHOR + "\n" + CSS_BLOCK, 1)

    UI.write_text(u, encoding="utf-8")
    CSS.write_text(c, encoding="utf-8")
    if not ready():
        print("ERROR: patch applied but verification failed", file=sys.stderr)
        return 2
    print(f"OK: applied qimen-grid mobile fix → {WEBUI}/static/{{ui.js,style.css}}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

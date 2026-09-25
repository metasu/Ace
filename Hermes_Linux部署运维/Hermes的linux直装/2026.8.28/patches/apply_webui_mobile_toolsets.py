#!/usr/bin/env python3
"""Apply mobile Toolsets/MCP entry into hermes-webui static files (idempotent).

Upstream hides #composerToolsetsWrap on narrow screens (#1431) but the mobile
overflow panel lacked a Toolsets action — phones could not pick MCP servers.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

WEBUI = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes/hermes-webui")
HTML = WEBUI / "static" / "index.html"
UI = WEBUI / "static" / "ui.js"
BOOT = WEBUI / "static" / "boot.js"

MOBILE_ACTION = """            <button class="composer-mobile-config-action" id="composerMobileToolsetsAction" type="button" onclick="toggleToolsetsDropdown()" title="Session toolsets / MCP" aria-label="Session toolsets / MCP" aria-haspopup="true" aria-expanded="false" aria-controls="composerToolsetsDropdown">
              <span class="composer-mobile-config-icon" aria-hidden="true"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg></span>
              <span class="composer-mobile-config-copy"><span class="composer-mobile-config-kicker" data-i18n="composer_mobile_toolsets">Toolsets / MCP</span><span class="composer-mobile-config-value" id="composerMobileToolsetsLabel">Active profile defaults</span></span>
            </button>
"""

APPLY_CHIP = '''function _applyToolsetsChip(toolsets) {
  _currentSessionToolsets = toolsets;
  const wrap = $('composerToolsetsWrap');
  const label = $('composerToolsetsLabel');
  const chip = $('composerToolsetsChip');
  const mobileLabel = $('composerMobileToolsetsLabel');
  const mobileAction = $('composerMobileToolsetsAction');
  // Always keep the wrap in the DOM so CSS can control visibility responsively.
  // Do NOT set wrap.style.display here — that would override the CSS media-query
  // rules that hide/show the chip based on container width (#1431). The chip is
  // tracked so /api/session/toolsets continues to work for cron/scripted
  // callers even when the chip itself is hidden on narrow screens.
  if (!label) return;
  const hasCustom = Array.isArray(toolsets) && toolsets.length > 0;
  const stagedSuffix = (!S || !S.session) ? ' *' : '';
  if (chip) chip.classList.toggle('active', hasCustom);
  if (hasCustom) {
    label.textContent = toolsets.join(', ') + stagedSuffix;
    label.classList.add('custom');
    if (chip) chip.title = t('session_toolsets') + ': ' + toolsets.join(', ') + stagedSuffix;
  } else {
    label.textContent = t('session_toolsets_profile_defaults');
    label.classList.remove('custom');
    if (chip) chip.title = t('session_toolsets') + ': ' + t('session_toolsets_profile_defaults');
  }
  if (mobileLabel) mobileLabel.textContent = label.textContent;
  if (mobileAction) {
    mobileAction.classList.toggle('active', hasCustom);
    mobileAction.setAttribute('aria-expanded', 'false');
    if (chip && chip.title) mobileAction.title = chip.title;
    else mobileAction.title = t('session_toolsets') + ': ' + label.textContent;
  }
}'''

POS = '''function _positionToolsetsDropdown() {
  const dd = $('composerToolsetsDropdown');
  const chip = $('composerToolsetsChip');
  const mobileAction = $('composerMobileToolsetsAction');
  const footer = document.querySelector('.composer-footer');
  if (!dd || !footer) return;
  const panel = $('composerMobileConfigPanel');
  const chipVisible = !!(chip && chip.offsetParent !== null);
  const mobileVisible = !!(mobileAction && mobileAction.offsetParent !== null);
  const anchor = (panel && panel.classList.contains('open') && mobileVisible)
    ? mobileAction
    : (chipVisible ? chip : (mobileVisible ? mobileAction : null));
  if (!anchor) { closeToolsetsDropdown(); return; }
  const chipRect = anchor.getBoundingClientRect();
  const footerRect = footer.getBoundingClientRect();
  let left = chipRect.left - footerRect.left;
  const maxLeft = Math.max(0, footer.clientWidth - dd.offsetWidth);
  left = Math.max(0, Math.min(left, maxLeft));
  dd.style.left = left + 'px';
}'''

TOGGLE = '''function toggleToolsetsDropdown() {
  const dd = $('composerToolsetsDropdown');
  const chip = $('composerToolsetsChip');
  const mobileAction = $('composerMobileToolsetsAction');
  if (!dd) return;
  const chipVisible = !!(chip && chip.offsetParent !== null);
  const mobileVisible = !!(mobileAction && mobileAction.offsetParent !== null);
  // Narrow screens hide the footer chip (#1431); open via mobile overflow action instead.
  if (!chipVisible && !mobileVisible) return;
  const open = dd.classList.contains('open');
  if (open) { closeToolsetsDropdown(); return; }
  if (typeof closeProfileDropdown === 'function') closeProfileDropdown();
  if (typeof closeWsDropdown === 'function') closeWsDropdown();
  closeModelDropdown();
  if (typeof closeReasoningDropdown === 'function') closeReasoningDropdown();
  _syncToolsetsChip();
  _populateToolsetsDropdown();
  dd.classList.add('open');
  if (chip) chip.classList.add('active');
  if (mobileAction) {
    mobileAction.classList.add('active');
    mobileAction.setAttribute('aria-expanded', 'true');
  }
  _positionToolsetsDropdown();
  const state = $('toolsetsDropdownState');
  const input = $('toolsetsInput');
  _loadToolsetsCatalog().then(function() {
    _renderToolsetsPresetSections({ state, input });
  }).catch(function() {
    _renderToolsetsPresetSections({ state, input });
  });
  setTimeout(() => { const inp = $('toolsetsInput'); if (inp) inp.focus(); }, 50);
}'''

CLOSE = '''function closeToolsetsDropdown() {
  const dd = $('composerToolsetsDropdown');
  const chip = $('composerToolsetsChip');
  const mobileAction = $('composerMobileToolsetsAction');
  if (dd) dd.classList.remove('open');
  if (chip) chip.classList.remove('active');
  if (mobileAction) {
    mobileAction.classList.remove('active');
    mobileAction.setAttribute('aria-expanded', 'false');
  }
}'''


def ready() -> bool:
    if not (HTML.is_file() and UI.is_file() and BOOT.is_file()):
        return False
    h, u, b = HTML.read_text(encoding="utf-8", errors="ignore"), UI.read_text(encoding="utf-8", errors="ignore"), BOOT.read_text(encoding="utf-8", errors="ignore")
    return (
        'id="composerMobileToolsetsAction"' in h
        and "composerMobileToolsetsAction" in u
        and "Narrow screens hide the footer chip" in u
        and "composerMobileToolsetsAction" in b
    )


def patch_html(text: str) -> str:
    text = text.replace(
        'aria-label="Workspace, model, quota, reasoning, and context settings"',
        'aria-label="Workspace, model, quota, reasoning, toolsets/MCP, and context settings"',
    )
    text = text.replace(
        'title="Workspace, model, quota, reasoning, and context settings"',
        'title="Workspace, model, quota, reasoning, toolsets/MCP, and context settings"',
    )
    if 'id="composerMobileToolsetsAction"' in text:
        return text
    i = text.find('id="composerMobileReasoningAction"')
    if i < 0:
        raise RuntimeError("composerMobileReasoningAction not found in index.html")
    end = text.find("</button>", i)
    if end < 0:
        raise RuntimeError("reasoning button end not found")
    end += len("</button>")
    return text[:end] + "\n" + MOBILE_ACTION + text[end:]


def patch_ui(text: str) -> str:
    text = text.replace(
        "const _MOBILE_CONFIG_BASE_LABEL='Workspace, model, quota, reasoning, and context settings';",
        "const _MOBILE_CONFIG_BASE_LABEL='Workspace, model, quota, reasoning, toolsets/MCP, and context settings';",
    )
    for name, body in (
        (r"function _applyToolsetsChip\(toolsets\) \{[\s\S]*?\n\}", APPLY_CHIP),
        (r"function _positionToolsetsDropdown\(\) \{[\s\S]*?\n\}", POS),
        (r"function toggleToolsetsDropdown\(\) \{[\s\S]*?\n\}", TOGGLE),
        (r"function closeToolsetsDropdown\(\) \{[\s\S]*?\n\}", CLOSE),
    ):
        m = re.search(name, text)
        if not m:
            raise RuntimeError(f"pattern not found: {name}")
        text = text[: m.start()] + body + text[m.end() :]

    old_co = """  if (
    !e.target.closest('#composerToolsetsChip') &&
    !e.target.closest('#composerToolsetsDropdown')
  ) closeToolsetsDropdown();"""
    new_co = """  if (
    !e.target.closest('#composerToolsetsChip') &&
    !e.target.closest('#composerMobileToolsetsAction') &&
    !e.target.closest('#composerToolsetsDropdown')
  ) closeToolsetsDropdown();"""
    if "composerMobileToolsetsAction" not in text.split("closeToolsetsDropdown();")[0][-200:] or old_co in text:
        if old_co in text:
            text = text.replace(old_co, new_co, 1)
        elif "!e.target.closest('#composerMobileToolsetsAction')" not in text:
            # already partially patched or different formatting
            text2 = text.replace(
                "!e.target.closest('#composerToolsetsChip') &&\n    !e.target.closest('#composerToolsetsDropdown')",
                "!e.target.closest('#composerToolsetsChip') &&\n    !e.target.closest('#composerMobileToolsetsAction') &&\n    !e.target.closest('#composerToolsetsDropdown')",
                1,
            )
            text = text2

    old_rs = """window.addEventListener('resize', () => {
  const dd = $('composerToolsetsDropdown');
  if (!dd || !dd.classList.contains('open')) return;
  const chip = $('composerToolsetsChip');
  if (!chip || chip.offsetParent === null) { closeToolsetsDropdown(); return; }
  _positionToolsetsDropdown();
});"""
    new_rs = """window.addEventListener('resize', () => {
  const dd = $('composerToolsetsDropdown');
  if (!dd || !dd.classList.contains('open')) return;
  const chip = $('composerToolsetsChip');
  const mobileAction = $('composerMobileToolsetsAction');
  const chipVisible = !!(chip && chip.offsetParent !== null);
  const mobileVisible = !!(mobileAction && mobileAction.offsetParent !== null);
  if (!chipVisible && !mobileVisible) { closeToolsetsDropdown(); return; }
  _positionToolsetsDropdown();
});"""
    if old_rs in text:
        text = text.replace(old_rs, new_rs, 1)

    old_mco = """  if(
    e.target.closest('#composerMobileConfigBtn') ||
    e.target.closest('#composerMobileConfigPanel') ||
    e.target.closest('#composerWsDropdown') ||
    e.target.closest('#composerModelDropdown') ||
    e.target.closest('#composerReasoningDropdown')
  ) return;
  closeMobileComposerConfig();"""
    new_mco = """  if(
    e.target.closest('#composerMobileConfigBtn') ||
    e.target.closest('#composerMobileConfigPanel') ||
    e.target.closest('#composerWsDropdown') ||
    e.target.closest('#composerModelDropdown') ||
    e.target.closest('#composerReasoningDropdown') ||
    e.target.closest('#composerToolsetsDropdown')
  ) return;
  closeMobileComposerConfig();"""
    if old_mco in text:
        text = text.replace(old_mco, new_mco, 1)
    elif "e.target.closest('#composerToolsetsDropdown')" not in text:
        text = text.replace(
            "e.target.closest('#composerReasoningDropdown')\n  ) return;\n  closeMobileComposerConfig();",
            "e.target.closest('#composerReasoningDropdown') ||\n    e.target.closest('#composerToolsetsDropdown')\n  ) return;\n  closeMobileComposerConfig();",
            1,
        )
    return text


def patch_boot(text: str) -> str:
    if "composerMobileToolsetsAction" in text:
        return text
    text2 = text.replace(
        "selectors:['#composerToolsetsWrap'],orderSelector:'#composerToolsetsWrap',orderGroup:'left'}",
        "selectors:['#composerToolsetsWrap','#composerMobileToolsetsAction'],orderSelector:'#composerToolsetsWrap',orderGroup:'left'}",
        1,
    )
    if text2 == text:
        text2 = text.replace(
            "selectors:['#composerToolsetsWrap']",
            "selectors:['#composerToolsetsWrap','#composerMobileToolsetsAction']",
            1,
        )
    return text2


def main() -> int:
    if not WEBUI.is_dir():
        print(f"SKIP: webui dir missing: {WEBUI}")
        return 0
    if ready():
        print(f"OK: mobile Toolsets/MCP entry already present in {WEBUI}")
        return 0
    for p in (HTML, UI, BOOT):
        if not p.is_file():
            print(f"ERROR: missing {p}", file=sys.stderr)
            return 1
    HTML.write_text(patch_html(HTML.read_text(encoding="utf-8")), encoding="utf-8")
    UI.write_text(patch_ui(UI.read_text(encoding="utf-8")), encoding="utf-8")
    BOOT.write_text(patch_boot(BOOT.read_text(encoding="utf-8")), encoding="utf-8")
    if not ready():
        print("ERROR: patch applied but verification failed", file=sys.stderr)
        return 2
    print(f"OK: applied mobile Toolsets/MCP entry → {WEBUI}/static/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

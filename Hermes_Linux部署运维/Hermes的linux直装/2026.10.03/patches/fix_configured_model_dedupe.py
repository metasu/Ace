#!/usr/bin/env python3
"""Dedupe ``provider/model`` composite badge keys in the WebUI model picker.

``configured_model_badges`` emits three key spellings per configured entry
(``model``, ``provider/model``, ``@provider:model``). The picker's
``_isEquivalentConfiguredModelEntry`` dedupes bare ids and ``@provider:``
variants, but a two-slash composite like ``atlascloud-grok-4.3/xai/grok-4.3``
normalizes to ``xai/grok.4.3`` while the group option ``xai/grok-4.3``
normalizes to ``grok.4.3`` — so a redundant second row was appended for every
vendor-prefixed model (grok-4.3, grok-4.6, gpt-sol-codex6 each showed twice).

Fix: treat ``<provider>/<model>`` as an equivalent routing spelling the same
way ``@<provider>:<model>`` already is — strip the provider prefix and compare
the remainder against same-provider picker rows.
"""
from __future__ import annotations

import sys
from pathlib import Path

WEBUI = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes/hermes-webui")
UI = WEBUI / "static" / "ui.js"

OLD = """  const rawId=String(modelId||'');
  const prefix=provider?`@${provider}:`:'';
  if(!prefix||!rawId.toLowerCase().startsWith(prefix)) return false;
  const routedId=rawId.slice(prefix.length);
  return (entries||[]).some(entry=>
    String(entry.providerId||'').toLowerCase()===provider
    &&_normalizeConfiguredModelKey(entry.value)===_normalizeConfiguredModelKey(routedId)
  );"""

NEW = """  const rawId=String(modelId||'');
  const rawLower=rawId.toLowerCase();
  const prefixes=provider?[`@${provider}:`,`${provider}/`]:[];
  for(const prefix of prefixes){
    if(!rawLower.startsWith(prefix)) continue;
    const routedId=rawId.slice(prefix.length);
    if((entries||[]).some(entry=>
      String(entry.providerId||'').toLowerCase()===provider
      &&_normalizeConfiguredModelKey(entry.value)===_normalizeConfiguredModelKey(routedId)
    )) return true;
  }
  return false;"""


def main() -> int:
    text = UI.read_text(encoding="utf-8")
    if NEW in text:
        print("fix_configured_model_dedupe: already applied")
        return 0
    if OLD not in text:
        print("fix_configured_model_dedupe: WARN target block not found (upstream changed?)")
        return 1
    UI.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    print("fix_configured_model_dedupe: applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

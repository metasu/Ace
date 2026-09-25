#!/usr/bin/env python3
"""Skip ``None`` chunks yielded by the OpenAI SDK stream iterator (idempotent).

Some OpenAI-compatible gateways (xiaoyiapi) emit a bare ``data: null`` SSE
frame between the finish chunk and the trailing usage chunk. The SDK decodes
it to ``None`` and Hermes then crashes at ``chunk.choices``
('NoneType' object has no attribute 'choices'), which surfaces as
"Response remained truncated after N continuation attempts".

Re-run after a hermes-agent upgrade so the guard survives source replacement.
"""
from __future__ import annotations

import sys
from pathlib import Path

HERMES_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else "/opt/hermes")
HELPERS = HERMES_DIR / "hermes-agent" / "agent" / "chat_completion_helpers.py"

OLD = '''def _iter_provider_stream_chunks(stream, *, response: Any = None):
    """Yield SDK chunks while translating SDK-level SSE decode failures."""
    try:
        yield from stream
'''

NEW = '''def _iter_provider_stream_chunks(stream, *, response: Any = None):
    """Yield SDK chunks while translating SDK-level SSE decode failures."""
    try:
        for chunk in stream:
            # Deploy-local: third-party gateways may emit `data: null` SSE
            # frames; the SDK decodes them to None chunks.
            if chunk is None:
                continue
            yield chunk
'''


def ready() -> bool:
    if not HELPERS.is_file():
        return False
    return "if chunk is None:" in HELPERS.read_text(encoding="utf-8", errors="ignore")


def main() -> int:
    if not HELPERS.is_file():
        print(f"SKIP: hermes-agent missing: {HELPERS.parent.parent}")
        return 0
    text = HELPERS.read_text(encoding="utf-8")
    if "if chunk is None:" in text:
        print("OK: null-chunk guard already installed")
        return 0
    if OLD not in text:
        print("ERROR: _iter_provider_stream_chunks hook site not found (upstream changed?)", file=sys.stderr)
        return 1
    HELPERS.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    print("OK: installed null-chunk guard in _iter_provider_stream_chunks")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Fix venv/pyvenv.cfg to point at portable Python (anti-drive-drift).

Usage: python fix_pyvenv.py <rely_dir>
  <rely_dir> should be the absolute path to the rely directory (e.g. F:\rely)

This rewrites the 'home = ...' line in <rely_dir>/venv/pyvenv.cfg to point
at <rely_dir>/python, so the venv's base interpreter resolves correctly
regardless of which drive letter the portable drive is mounted as.
"""
import pathlib
import re
import sys


def main():
    if len(sys.argv) < 2:
        print("[fix_pyvenv] ERROR: missing rely_dir argument", file=sys.stderr)
        return 1
    rely = pathlib.Path(sys.argv[1]).resolve()
    cfg = rely / "venv" / "pyvenv.cfg"
    if not cfg.exists():
        print(f"[fix_pyvenv] SKIP - {cfg} not found")
        return 0

    pyhome = str((rely / "python").resolve())
    text = cfg.read_text(encoding="utf-8")
    new = re.sub(r"^home\s*=.*$", lambda m: f"home = {pyhome}", text, flags=re.M)
    if new != text:
        cfg.write_text(new, encoding="utf-8", newline="\n")
        print(f"[fix_pyvenv] OK - home rewritten to {pyhome}")
    else:
        print(f"[fix_pyvenv] OK - home already correct ({pyhome})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

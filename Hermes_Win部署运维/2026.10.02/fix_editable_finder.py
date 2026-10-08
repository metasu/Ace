r"""Fix editable-install finder paths to current drive (anti-drive-drift).

Usage: python fix_editable_finder.py <rely_dir> <root_dir>
  <rely_dir>  absolute path to the rely directory (e.g. D:\rely)
  <root_dir>  absolute path to the hermes_ui directory (e.g. D:\hermes_ui)

When the portable bundle is moved to a different drive letter, the
__editable___hermes_agent_*_finder.py file in venv site-packages still
contains the old drive letter (e.g. F:\\hermes_ui\\hermes-agent\\...).
This script rewrites every path that ends with \\hermes-agent\\... to
use the current <root_dir>\\hermes-agent\\..., making the editable
install work regardless of which drive the bundle is mounted on.
"""
import pathlib
import re
import sys


def main():
    if len(sys.argv) < 3:
        print("[fix_editable_finder] ERROR: missing arguments", file=sys.stderr)
        return 1
    rely = pathlib.Path(sys.argv[1]).resolve()
    root = pathlib.Path(sys.argv[2]).resolve()

    sp = rely / "venv" / "Lib" / "site-packages"
    if not sp.exists():
        print(f"[fix_editable_finder] SKIP - {sp} not found")
        return 0

    # Find the editable finder file
    candidates = list(sp.glob("__editable___hermes_agent_*_finder.py"))
    if not candidates:
        print("[fix_editable_finder] SKIP - no editable finder file found")
        return 0

    # The canonical hermes-agent source dir under root
    agent_src = str(root / "hermes-agent")
    # In the finder file, backslashes are doubled (Python string literals)
    agent_src_escaped = agent_src.replace("\\", "\\\\")

    changed = False
    for finder_file in candidates:
        text = finder_file.read_text(encoding="utf-8")
        # Replace any drive-letter-prefixed path containing hermes-agent.
        # Match: <letter>: + one-or-more backslashes + ... + hermes-agent
        # Use a lambda for replacement so re.sub doesn't interpret backslashes.
        new = re.sub(
            r"[A-Za-z]:[\\]+[^']*?hermes-agent",
            lambda m: agent_src_escaped,
            text,
        )
        if new != text:
            finder_file.write_text(new, encoding="utf-8")
            print(f"[fix_editable_finder] OK - paths rewritten to {agent_src_escaped} in {finder_file.name}")
            changed = True
        else:
            print(f"[fix_editable_finder] OK - paths already correct in {finder_file.name}")

    if not changed:
        print("[fix_editable_finder] OK - no changes needed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

---
name: windows-portable-hermes
description: "Audit, explain, launch, and harden the user's Windows USB/portable Hermes layout (hermes_ui + sibling rely, start.bat self-heal). Use when the user mentions F:\\hermes_ui, portable Hermes, drive-letter drift, MCP path fix, fix_mcp_paths, fix_pyvenv, start.bat launcher, or moving Hermes between PCs."
---

# Windows Portable Hermes

Class skill for the user's **portable Hermes on a removable drive**, not for stock Hermes install docs.

## Canonical layout

On the portable volume (letter may be `F:`, `E:`, `D:`, ...):

```text
<DRIVE>:\
  hermes_ui\          # app + data + MCP + launcher
    start.bat
    fix_mcp_paths.py
    fix_pyvenv.py
    data\             # HERMES_HOME
    hermes-agent\
    hermes-webui\
    mcp\              # portable MCP servers (build + node_modules)
    output\           # MCP DEFAULT_OUTPUT_PATH
  rely\               # REQUIRED sibling runtime
    python\
    venv\
    node\
    git\
    uv\
```

**Invariant:** `hermes_ui` and `rely` must stay **siblings on the same volume**. Copying only `hermes_ui` breaks the install.

## Always launch via start.bat

`start.bat` is the control plane. It:

1. Sets `ROOT_DIR=%~dp0` (no hardcoded drive letter)
2. Resolves `RELY_DIR` to `..\rely` as a fully-qualified path
3. Sets `HERMES_HOME=%ROOT_DIR%data` and `HERMES_WEBUI_STATE_DIR=%ROOT_DIR%data\webui`
4. Sets `HERMES_GIT_BASH_PATH=%RELY_DIR%git\bin\bash.exe`
5. Prepends portable `venv\Scripts`, `node`, `git\bin` to `PATH` once per window
6. Runs preflight checks
7. Runs `fix_pyvenv.py` against current `rely`
8. Runs `fix_mcp_paths.py` against current `hermes_ui`
9. Starts gateway / WebUI by calling `%RELY_DIR%venv\Scripts\python.exe` **directly** (never `activate`)

### User-facing rule

- **Via `start.bat` → drive-letter drift is handled.**
- **Bypassing bat** (raw `python -m hermes_cli...`, IDE run, manual env) → MCP args / `DEFAULT_OUTPUT_PATH` / `pyvenv.cfg` may still point at the old letter.

When the user asks “换盘 / 换电脑能不能用”, answer that distinction first.

## What auto-heals vs what does not

### Auto-healed by start.bat

| Item | Mechanism |
|------|-----------|
| `rely\venv\pyvenv.cfg` `home=` | `fix_pyvenv.py` rewrites to `<rely>\python` |
| `data\config.yaml` MCP `args` `...\mcp\...\build\index.js` | `fix_mcp_paths.py` rewrites drive prefix |
| `DEFAULT_OUTPUT_PATH` under MCP env | rewritten to `<root>\output` |
| `HERMES_HOME` / WebUI state / Git Bash path | env injection from `ROOT_DIR` / `RELY_DIR` |

### Not healed (expect machine-local breakage)

| Item | Why |
|------|-----|
| `data\webui\last_workspace.txt` | often a host path like `C:\Users\...\workspace` |
| Chat / skill / memory absolute paths (`P:\sync\...`, other host dirs) | content, not launcher state |
| One-off scripts hardcoding `F:\hermes_ui\...` (e.g. cleanup helpers) | not in fix pipeline |
| Secrets living in bat / MCP env | portable convenience, not security isolation |

### Low priority / do not treat as main failure

`rely\venv\Scripts\activate*` (and some shebangs like `jp.py`) may still reference **old layout** `F:\hermes_ui\venv`.

- **Daily Hermes path does not use activate** — bat calls `venv\Scripts\python.exe` directly.
- `activate.ps1` is already self-locating; shell `activate` / `activate.bat` / fish / csh / nu may be stale.
- **Do not urge fixing activate unless** the user manually activates for debugging, or is deliberately polishing the portable kit.
- Prefer advice: use bat or absolute `rely\venv\Scripts\python.exe`; optional later rebuild of venv cleans activate files.

## Audit checklist (when asked to inspect the portable install)

1. Confirm volume letter and sibling layout: `<drive>\hermes_ui` + `<drive>\rely`.
2. Read `start.bat` — expect `%~dp0` + `..\rely`, not hardcoded `F:\`.
3. Confirm fix scripts exist next to bat: `fix_pyvenv.py`, `fix_mcp_paths.py`.
4. Confirm six MCP entrypoints under `hermes_ui\mcp\*\build\index.js`.
5. Dry-run fix scripts with current roots; expect “already correct” or a rewrite to current letter.
6. Scan `data\config.yaml` for drive-absolute MCP paths (OK if bat rewrites them).
7. Check `last_workspace.txt` and mention host-local workspace risk.
8. Separate **launcher portability** from **cross-machine file access** (`terminal.backend: local` can see any local disk that exists; it cannot see another PC’s `C:` / `P:`).

Do **not** dump full `.env` / API keys. Status only: present / missing / has absolute paths.

## Design evaluation tone (if user asks “is this genius?”)

Be honest and specific:

- Strong practical engineering for Windows USB Hermes: self-locating launcher + sibling runtime + startup path rewrite.
- Not pure structural purity: configs still store absolute paths and rely on launcher compensation.
- Grade as **first-tier practical portable design**, not academic perfection.

## Hardening direction (only if user wants next-level work)

Prefer in this order:

1. Keep requiring bat (or a single entrypoint) for all launches.
2. Move toward relative / env-placeholder MCP paths so rewrite is optional.
3. Default workspace to an on-volume path or explicit picker after move.
4. Split secrets from the stick (host override env) while keeping runtime portable.
5. Rebuild venv when doing a dependency refresh so activate scripts match `rely\venv`.

## Model context-window troubleshooting

When the WebUI context indicator is smaller than the selected model's published window, do not infer model impersonation or blindly edit session JSON. Separate four layers:

1. **Model catalog metadata** — the model family's published context and output limits.
2. **Provider endpoint limit** — the selected gateway may impose a smaller limit; inspect its `/models` response, but note that OpenAI-compatible endpoints often return only model IDs.
3. **Hermes resolution** — inspect `model.context_length`, custom-provider per-model metadata, persistent endpoint cache, and the resolver's precedence.
4. **Session snapshot** — an existing session can retain the context length recorded on an earlier call even after configuration changes.

If the provider confirms the model ID but omits context metadata, and the trusted catalog has a current value, set `model.context_length` explicitly for the configured default model using the official CLI. Verify both the low-level metadata resolver and the WebUI session-model resolver. Start a new session or restart after changing configuration; do not rewrite an active session snapshot merely to change the indicator.

The global `model.context_length` override is intended for `model.default`; verify the WebUI's default-model guard before relying on it so fallback or switched models keep their own limits. A client-side context value cannot expand a provider's server-side allowance.

For the concrete probe and repair sequence, load `references/model-context-window-resolution.md`.

## Communication

- User prefers Chinese.
- Prefer decisive conclusions (“经 bat 启动就没问题 / activate 先别改”) over long option dumps, then a short table if needed.
- Distinguish verified model ID, catalog metadata, provider-enforced context, and unverifiable underlying weights. Never claim official direct service or authentic weights from a model slug alone.
- When correcting a context mismatch, report the old source, configured value, resolver verification, and restart/new-session requirement.
- Never present host-only paths as portable failures of Hermes itself.

## References

- `references/portable-layout-audit.md` — concrete findings from the F: install audit (what was healthy vs residual).
- `references/model-context-window-resolution.md` — diagnose and repair context-window mismatches across catalog metadata, provider endpoints, Hermes config/cache, and session snapshots.

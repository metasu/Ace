# Shared Standard + Machine Baseline Consolidation

## Trigger

Use this reference when two large Markdown files mix cross-machine engineering rules with host-specific paths, versions, and troubleshooting, and the user asks to "整合精简" or otherwise consolidate them.

## Audit Matrix

| Content class | Shared standard | Machine baseline | Reference file |
|---|---:|---:|---:|
| Evidence-first workflow | Yes | Link only | No |
| Credential/source-of-truth rules | Yes | Local injection path only | Detailed provider evidence if long |
| Shell and encoding discipline | Yes | Local shell anomaly only | Long transcripts if needed |
| Absolute executable paths | No | Yes | No |
| Version snapshots | No | Yes, with observation date | Historical snapshots if useful |
| Proxy protocol-selection method | Yes | No | Optional probe script |
| Local proxy executable/port | No | Yes | No |
| Generic media acceptance | Yes | Link only | No |
| Local media tool entry point | No | Yes | No |
| Sync-drive or filesystem quirk | No | Yes | Reproduction details if long |
| Final generic checklist | Yes | Host-only supplement | No |

## High-Value Merge Patterns

### Workflow + final checklist

If “evidence first,” “standard workflow,” and “final checklist” repeat the same obligations, keep:

- one short evidence loop;
- one ordered execution workflow;
- one compact final checklist that links to domain-specific acceptance sections.

Do not preserve three paraphrased lists.

### Configuration source + runtime mirror

Keep credential isolation, source-code verification, generated mirror behavior, and end-to-end validation in one configuration-security section. A generated `auth.json`-style mirror should not also appear as two separate generic failures unless each entry adds distinct recovery information.

### Shell misdetection

Merge “Windows command discipline,” “PowerShell command not found,” and “first PowerShell command fails” into one rule and one failure lookup. Machine-specific terminal wrappers or drive behavior stay in the baseline.

### Media commands

Keep `ffmpeg`/`ffprobe` acceptance commands in the shared standard. The machine baseline should provide the local renderer/CLI/browser path and point to shared acceptance criteria.

### Long local failure recipes

For a virtual or synchronized drive that sometimes hides directory output, retain:

- symptom;
- suspected local mechanism;
- one primary deterministic verification method;
- one special decoder only if it handles a distinct artifact format.

Remove multiple fallback implementations that prove the same fact unless the primary method is unavailable in a supported environment.

## Suggested Main Shapes

Shared standard:

1. Scope and baseline links
2. Core principles
3. Standard workflow
4. Configuration and credential safety
5. Files, encoding, shell, installation
6. Domain acceptance standards
7. Failure lookup
8. Final verification and maintenance

Machine baseline:

1. Host and workspace
2. Runtime/tool tables
3. Local domain tool entry points
4. Local proxy/services
5. Machine-specific failures
6. Host verification supplement and maintenance

## Mechanical Validation Recipes

Use the environment's approved search/read tools. The checks conceptually are:

```text
line and byte counts before/after
count lines beginning with ``` and require an even result
list headings and detect duplicates
search the entire standards directory for references to removed section numbers
verify every linked sibling filename exists
search for each preservation invariant and key tool name
```

Example invariants for a Windows developer baseline:

- each Python environment and its role;
- isolated Rust homes and requested toolchain;
- framework MSRV/system/project dependency distinction;
- MSVC/WebView prerequisites;
- local proxy process/port and per-process scope;
- document automation save/close rule;
- video lint/audio acceptance;
- synchronized-drive recovery path;
- local TTS model/venv/GPU entry point.

## Result Reporting

A useful completion report states:

- old and new versions;
- old/new total lines and bytes, plus percentages;
- the new ownership boundary;
- the main duplicate groups removed;
- any sibling file changed solely to repair links;
- balanced fences, valid links, zero stale section references, and retained invariants.

Avoid describing every editorial sentence-level change. The point is to prove the standards library is smaller, navigable, and still operational.

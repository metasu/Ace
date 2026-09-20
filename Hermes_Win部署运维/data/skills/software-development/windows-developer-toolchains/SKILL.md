---
name: windows-developer-toolchains
description: "Use when installing, reinstalling, relocating, repairing, or verifying language toolchains on Windows, especially into a custom directory or through a local proxy. Covers state inspection, isolated homes, interrupted downloads, per-process proxy injection, progress reporting, and end-to-end compile/run verification."
version: 1.1.0
author: Hermes Agent
license: MIT
platforms: [windows]
metadata:
  hermes:
    tags: [windows, toolchains, installation, proxy, verification]
    related_skills: [systematic-debugging, windows-portable-hermes]
---

# Windows Developer Toolchains

## Overview

Install and repair language toolchains on Windows with evidence at every stage. This skill applies to Rust, Go, Node.js, Python, Java, and similar developer runtimes when the user wants a custom location, an isolated installation, a proxy-assisted download, or recovery from an interrupted installer.

The completion standard is not "the installer exited successfully." A toolchain is complete only after its binaries report the requested version and it compiles or executes a minimal real program using the intended installation state.

## When to Use

Use this skill when the user asks to:

- install or reinstall a compiler/runtime/SDK on Windows;
- place it under a non-default directory or removable drive;
- avoid changing global `PATH` or global proxy settings;
- recover from partial downloads or an interrupted installation;
- accelerate downloads through a local proxy client;
- verify whether an earlier installation actually completed.

Do not use it for ordinary project dependency installation inside an already-working toolchain, or for Hermes-specific portable runtime repair; use `windows-portable-hermes` for the latter.

## Workflow

### 1. Establish the exact target

Record the requested product version, host triple/architecture when applicable, installation root, required component/profile set, and whether global environment changes are allowed.

Treat the user's custom directory as the ownership boundary. Do not silently fall back to `%USERPROFILE%`, system-wide installers, or a different version.

Completion criterion: one explicit target tuple exists, for example `Rust 1.97.1 + x86_64-pc-windows-msvc + D:\\tools\\rust + default profile + no global PATH edit`.

### 2. Inspect live state before changing it

Read any machine baseline, environment manifest, bootstrap script, or documented custom tool root before probing only the default `PATH` and user-home locations. Treat these observations separately:

- `command -v` / `where.exe` misses a binary: the current shell has no default entry point;
- `%USERPROFILE%` lacks the conventional tool directory: the default per-user location is absent;
- documented custom roots and explicit binaries are also absent or fail verification: only then classify the toolchain as absent.

When a custom root is documented, set its native home variables and invoke its binaries by explicit path before drawing an installation conclusion. Re-run version checks because baseline documents are discovery hints, not current-state proof.

Check:

- existing binaries and their actual versions;
- installer metadata and registered toolchains;
- directory size and partial/temp download markers;
- related running processes and file locks;
- free disk space;
- relevant local proxy processes and listening ports, if acceleration is requested.

A registered version is not proof of a complete installation. Correlate metadata with component files and runnable binaries.

Completion criterion: classify the state as absent, complete, partial/recoverable, or inconsistent, backed by command output.

### 3. Choose the least destructive recovery path

Prefer installer-native recovery or reinstall commands when they can reuse verified downloads. For clearly inconsistent state, remove only the affected toolchain/component through its package manager before reinstalling.

Do not delete an entire custom root without understanding whether it contains installers, caches, projects, or other user data. Preserve unrelated content and avoid destructive filesystem commands unless the user explicitly authorized them.

Completion criterion: the chosen operation has a narrow scope and a rollback/preservation story.

### 4. Validate acceleration before the long download

When using a local proxy:

1. Discover the actual running client and listening ports from live process/socket state.
2. Determine whether the port accepts HTTP CONNECT, SOCKS5, or both.
3. Probe the toolchain's real distribution endpoint with a short timeout.
4. Use the protocol/port combination that succeeds.
5. Inject proxy variables into only the installer process unless the user requested persistent configuration.

Do not assume conventional ports such as `7890`, `1080`, or `10808`. A listening port can still be the wrong protocol.

Completion criterion: a short probe reaches the actual distribution host through the selected proxy before installation begins.

### 5. Run and track the real installation

For a bounded operation that may take minutes, run it as a tracked background process with completion notification. Capture the process/session handle and inspect initial output promptly to confirm the requested version and that downloading has started.

Keep the user informed with short evidence-based updates at meaningful transitions:

- state inspection complete;
- acceleration path validated;
- installer started with the exact target;
- components downloading/recovering;
- installer exited;
- verification underway.

Never send a sequence of future-tense status messages without starting the corresponding command. If the user signals urgency, report the current live state first, then continue execution immediately.

Completion criterion: installer process exits successfully and its full output identifies the requested version/components.

### 6. Verify in layers

Run all applicable checks using the custom installation's explicit binary paths and isolated environment:

1. package/toolchain manager active-version output;
2. compiler/runtime verbose version and host architecture;
3. package manager version;
4. expected default components such as formatter/linter;
5. absence of stale partial-download markers;
6. plausible installed size and adequate remaining disk space;
7. compile and run a minimal program;
8. for installed script runners or package-manager tools, run an end-to-end artifact that exercises their defining feature (for example, `rust-script` with an embedded dependency), not only `--version`;
9. remove temporary verification artifacts.

Explicit paths prevent an unrelated system installation from producing a false pass.

Completion criterion: a generated executable/script runs and prints the expected marker while all requested versions match.

### 7. Separate toolchain readiness from framework/project readiness

When the user asks whether the toolchain supports a downstream framework, verify the framework's current minimum compiler/runtime version from live package metadata, then inspect its platform prerequisites. Do not infer compatibility only from the toolchain being "new."

Keep three layers distinct in the answer:

1. toolchain compatibility (for Rust, compare `rustc` with the framework crate/CLI MSRV);
2. system prerequisites (for example MSVC Build Tools and WebView2 for Tauri on Windows);
3. project dependencies installed from the repository's manifest and lockfile.

A missing optional global CLI is not a blocker when the project uses a local CLI. Conversely, a system-ready machine still needs each project's dependencies installed. For Tauri 2 checks, load `references/rust-desktop-framework-readiness.md`.

Completion criterion: the report says exactly which layer is ready and what, if anything, remains at project scope.

## Windows and MSYS Path Discipline

Hermes terminal sessions on Windows may run under Git Bash/MSYS. Environment values passed to native Windows programs can be transformed unexpectedly when written as POSIX paths.

- Prefer native values such as `D:\\tools\\rust` for Windows-native environment variables.
- Use `/d/tools/rust/program.exe` to invoke a Windows executable from Bash when convenient.
- Quote paths containing spaces.
- After setting a custom home variable, ask the native tool to print/show its state before starting a long operation.
- If a native tool resolves `/d/...` as `C:/d/...`, stop and replace the environment value with a native Windows path.

## User Communication

Installation tasks are execution tasks. Start the real operation promptly after prerequisite checks and never imply progress that has not occurred.

Status updates should include concrete evidence: active PID/session, current phase, component count, downloaded/installed size, or exact installer output. Avoid repeated promises such as "I will now install" without an accompanying tool call.

When the user is waiting, optimize for time-to-working-artifact: test the acceleration route quickly, launch the tracked install, and reserve detailed explanation for the final summary.

## Common Pitfalls

1. **Treating installer registration as success.** Verify binaries and compile/run a program.
2. **Using a guessed proxy port/protocol.** Inspect listeners and probe the real distribution host first.
3. **Changing global proxy/PATH for a one-time install.** Prefer per-process environment variables unless persistence is requested.
4. **Passing POSIX home paths to native Windows tools.** Use native Windows paths for their environment variables.
5. **Deleting the whole install root to clear partial state.** Use installer-native uninstall/recovery and preserve unrelated files.
6. **Letting a long foreground command vanish behind a timeout.** Use a tracked background process and wait/poll it to completion.
7. **Stopping after download or version output.** Compile and run a smoke program through the exact custom binary path.
8. **Using punctuation-heavy source names.** Some compilers derive module/crate identifiers from filenames; use a simple identifier or specify one explicitly.
9. **Narrating instead of executing.** Every claimed transition must correspond to an actual command/result.
10. **Equating framework support with global CLI installation.** Check current MSRV and platform prerequisites, then distinguish optional global tooling from repository-local dependencies.
11. **Saying "nothing needs installing" too broadly.** Say "no additional system software" when accurate, while noting that every project still installs its manifest/lockfile dependencies.

## Verification Checklist

- [ ] Requested version, architecture, root, profile/components, and global-change policy are explicit
- [ ] Existing state and running processes inspected
- [ ] Partial state classified without deleting unrelated data
- [ ] Proxy endpoint and protocol tested against the real distribution host when applicable
- [ ] Long installation tracked to a real exit code
- [ ] Exact custom binaries report the requested versions
- [ ] Expected formatter/linter/components are present
- [ ] Partial markers are gone or explained
- [ ] Minimal program compiled/executed successfully
- [ ] Temporary verification files removed
- [ ] Final report states installation paths and any persistent environment changes
- [ ] Downstream framework support is based on current MSRV/platform checks, not version intuition
- [ ] System prerequisites, optional global tools, and project-local dependencies are reported separately

## References

- `references/rustup-custom-home-and-local-proxy.md` - Rust-specific custom homes, MSYS path handling, interrupted-install recovery, VTO/v2rayN proxy probing, `rust-script` installation, and end-to-end verification commands.
- `references/rust-desktop-framework-readiness.md` - Tauri 2 and similar Rust desktop framework readiness: current MSRV checks, MSVC/WebView2 prerequisites, project-local dependencies, and optional global CLI boundaries.

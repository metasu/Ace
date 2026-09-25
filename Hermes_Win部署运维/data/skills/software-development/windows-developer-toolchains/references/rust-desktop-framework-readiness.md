# Rust Desktop Framework Readiness on Windows

Use this reference when the user asks whether an installed Rust toolchain is ready for Tauri 2 or another Rust desktop framework. The goal is to distinguish toolchain compatibility from project dependency installation and full Windows packaging readiness.

## Three separate questions

Do not collapse these into a single "installed/not installed" answer:

1. **Rust compatibility:** compare the installed `rustc` with the current crate/CLI `rust-version` (MSRV).
2. **Windows system prerequisites:** verify the MSVC C++ toolchain and the framework's web/runtime dependency, such as WebView2 for Tauri.
3. **Project dependencies:** inspect the project's lockfile/package manager and install its local CLI/API/crates as declared by that project.

A machine can be system-ready while a new project still needs `npm install`, Cargo dependency resolution, and its first compilation.

## Live checks

Use the intended custom Rust homes and explicit binary paths:

```bash
export RUSTUP_HOME='D:\milieu\rusttools\rustup'
export CARGO_HOME='D:\milieu\rusttools\cargo'
BIN='/d/milieu/rusttools/cargo/bin'

"$BIN/rustc.exe" --version
"$BIN/cargo.exe" --version
"$BIN/cargo.exe" search tauri --limit 3
"$BIN/cargo.exe" info tauri
"$BIN/cargo.exe" info tauri-cli
```

Treat registry/package-index versions as a dated snapshot. Query again whenever the user asks about "latest"; do not preserve a specific Tauri release as timeless fact.

Check Windows prerequisites from live state:

- use Visual Studio Installer `vswhere.exe` and require `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`;
- verify Microsoft Edge WebView2 Runtime in the Edge Update registry/client entries;
- verify Node.js and the project's selected JS package manager when the frontend uses one;
- distinguish Git Bash's unrelated `link.exe` from the MSVC linker. A `where link.exe` hit alone does not establish MSVC readiness.

## Tauri 2 dependency boundary

For ordinary Tauri projects, prefer a project-local JavaScript CLI so the repository controls the version:

```bash
npm install -D @tauri-apps/cli@latest
npm install @tauri-apps/api
```

For an existing project, honor its lockfile and package manager (`npm ci`, `npm install`, `bun install`, etc.) instead of blindly adding packages.

The Rust-side project normally declares `tauri` and `tauri-build` in `src-tauri/Cargo.toml`; Cargo resolves those during project setup/build. These are project dependencies, not missing system software.

A global Rust CLI is optional:

```bash
cargo install tauri-cli --version '^2' --locked
```

Only recommend/install it when the user specifically wants the `cargo tauri` global entry point. It compiles many crates and can take substantially longer than a project-local npm CLI.

## Reporting language

Use precise conclusions:

- **System-ready:** Rust satisfies the current MSRV, MSVC Build Tools and WebView2 are present, and the frontend runtime/package manager is available.
- **Project setup still required:** install dependencies declared by the repository and run its development/build command.
- **Not globally installed:** absence of `cargo-tauri` is not a blocker when the project uses `@tauri-apps/cli`.

Avoid saying simply "nothing needs installing" without the project-dependency qualification. The accurate formulation is: no additional system software is required; each project still installs its own dependencies.

## Verification escalation

Metadata checks establish compatibility, not a complete app build. If the user asks to build or verify Tauri itself, create or use a real project, run dependency installation, execute `tauri dev` or `tauri build`, and report the actual result. Do not claim packaging readiness solely from `cargo info` and prerequisite detection.

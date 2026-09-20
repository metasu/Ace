# Rustup Custom Home and Local Proxy on Windows

Use this reference when the requested Windows toolchain is Rust and any of these apply: custom install root, interrupted `rustup` state, Git Bash/MSYS shell, or a one-time VTO/v2rayN proxy.

## Custom directory layout

Rustup separates toolchain payloads from command shims and Cargo state:

```text
D:\milieu\rusttools\
  rustup\          # RUSTUP_HOME: toolchains, downloads, metadata
  cargo\           # CARGO_HOME: bin\rustup.exe, cargo.exe/rustc.exe shims
  rustup-init.exe  # optional retained installer
```

For native Windows executables launched from Git Bash, set native Windows values:

```bash
export RUSTUP_HOME='D:\milieu\rusttools\rustup'
export CARGO_HOME='D:\milieu\rusttools\cargo'
BIN='/d/milieu/rusttools/cargo/bin'
```

Do not set these homes to `/d/milieu/...` unless you have verified the native process receives the intended path. MSYS argument/environment conversion can turn it into an unintended path such as `C:/d/...`.

## Diagnose before reinstalling

Before checking only `PATH` or `%USERPROFILE%\.cargo`, read any machine baseline or environment manifest that may declare custom `CARGO_HOME` / `RUSTUP_HOME`. A missing `command -v rustc`, failed `where.exe rustc`, or absent default `.cargo` directory proves only that the conventional entry point is unavailable; it does not prove Rust is uninstalled.

For a documented custom root, first verify the shims and payload by explicit path:

```bash
export RUSTUP_HOME='D:\milieu\rusttools\rustup'
export CARGO_HOME='D:\milieu\rusttools\cargo'
BIN='/d/milieu/rusttools/cargo/bin'

for exe in rustup.exe rustc.exe cargo.exe; do
  test -f "$BIN/$exe" && printf 'FOUND %s\n' "$BIN/$exe"
done
```

Then run with the custom homes set:

```bash
"$BIN/rustup.exe" show
"$BIN/rustup.exe" toolchain list
"$BIN/rustc.exe" --version --verbose
"$BIN/cargo.exe" --version
```

Also inspect:

- `RUSTUP_HOME\downloads\*.partial` for interrupted downloads;
- `RUSTUP_HOME\toolchains\<toolchain>` size/content;
- live `rustup`, `rustc`, and `cargo` processes;
- disk space.

A toolchain shown by `rustup toolchain list` may still be partially installed. Missing/runnable binaries, tiny payload size, and `.partial` files are stronger evidence.

## Recover partial toolchains

Rustup can recover and reuse downloaded state. First retry the exact toolchain installation. If the registered toolchain is inconsistent and recovery does not work, remove only that toolchain through rustup, then install it again:

```bash
"$BIN/rustup.exe" toolchain uninstall 1.97.1-x86_64-pc-windows-msvc
"$BIN/rustup.exe" toolchain install 1.97.1-x86_64-pc-windows-msvc \
  --profile default --no-self-update
```

Avoid deleting the whole root because it may contain useful cache and the installer.

## VTO/v2rayN one-time proxy

VTO/v2rayN may expose several local ports with different protocols. Discover live listeners instead of assuming a port:

```bash
ps -W | grep -Ei 'v2rayN|xray|mihomo|sing-box' | grep -v grep || true
netstat -ano | grep LISTENING
```

Probe the actual Rust distribution endpoint with both likely protocols and a short timeout:

```bash
curl --proxy http://127.0.0.1:10808 \
  --connect-timeout 10 --max-time 30 \
  -fsS https://static.rust-lang.org/dist/channel-rust-<VERSION>.toml.sha256

curl --proxy socks5h://127.0.0.1:10808 \
  --connect-timeout 10 --max-time 30 \
  -fsS https://static.rust-lang.org/dist/channel-rust-<VERSION>.toml.sha256
```

Notes:

- A port accepting TCP may still reject HTTP CONNECT or SOCKS5.
- `socks5h` resolves DNS through the proxy.
- When probing with `curl -o /dev/null`, do not also use output patterns that make the shell/runtime report a write callback failure; a successful HTTP status still establishes reachability, but use a simpler probe on retry.
- Prefer the fastest verified combination, not a conventional port number.

Inject the proxy only into the installation process:

```bash
export HTTP_PROXY='http://127.0.0.1:10808'
export HTTPS_PROXY='http://127.0.0.1:10808'
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTPS_PROXY"
export RUSTUP_MAX_RETRIES=10

"$BIN/rustup.exe" toolchain install 1.97.1-x86_64-pc-windows-msvc \
  --profile default --no-self-update
```

This does not persistently modify Windows system proxy settings or global environment variables.

## Verification

Verify through explicit custom paths:

```bash
"$BIN/rustup.exe" show active-toolchain
"$BIN/rustc.exe" --version --verbose
"$BIN/cargo.exe" --version
"$BIN/cargo-clippy.exe" --version
"$BIN/rustfmt.exe" --version
```

Compile and run a minimal program. Use a punctuation-free source filename or pass `--crate-name` explicitly:

```rust
fn main() {
    println!("Rust toolchain OK");
}
```

```bash
"$BIN/rustc.exe" --crate-name rust_smoke \
  'C:\temp\rust_smoke.rs' \
  -o 'C:\temp\rust_smoke.exe'
/c/temp/rust_smoke.exe
```

Success requires the expected output and exit code 0. Then remove both temporary files and confirm no stale `.partial` downloads remain.

### MSVC initialization from Git Bash/MSYS

For an MSVC Rust target, direct `rustc` may need the Visual Studio linker environment. If a nested `cmd.exe /c 'call "...vcvars64.bat" && rustc ...'` command is fragile because Bash/MSYS and `cmd.exe` disagree about quoting or backslash conversion, write a short temporary `.cmd` file and invoke it by relative name from the intended working directory:

```cmd
@echo off
call "D:\path\to\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b %errorlevel%
set "RUSTUP_HOME=D:\path\to\rustup"
set "CARGO_HOME=D:\path\to\cargo"
"D:\path\to\cargo\bin\rustc.exe" --crate-name rust_smoke rust_smoke.rs -o rust_smoke.exe
if errorlevel 1 exit /b %errorlevel%
rust_smoke.exe
```

From Git Bash, run `cmd.exe /d /c rust_smoke.cmd` while the terminal working directory contains the file. Relative invocation avoids the extra Windows-path quoting layer. Clean up the `.cmd`, source, executable, and PDB after checking the output and exit code. This is a fallback for multi-shell quoting complexity, not evidence that either shell or toolchain is broken.

## Installing and verifying `rust-script`

Treat `rust-script` as a Cargo-installed tool inside the existing custom `CARGO_HOME`, not as a second Rust installation. Before installing, verify the active custom toolchain, query the current crate version, confirm registry reachability and disk space, and check whether the executable already exists:

```bash
export RUSTUP_HOME='D:\path\to\rustup'
export CARGO_HOME='D:\path\to\cargo'
BIN='/d/path/to/cargo/bin'

"$BIN/rustup.exe" show active-toolchain
"$BIN/cargo.exe" search rust-script --limit 3
test -f "$BIN/rust-script.exe" && "$BIN/rust-script.exe" --version
```

For an MSVC target, run installation through the initialized Visual Studio environment. When called from Git Bash/MSYS, use the temporary `.cmd` pattern from the previous section to avoid nested quoting failures:

```cmd
@echo off
call "D:\path\to\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b %errorlevel%
set "RUSTUP_HOME=D:\path\to\rustup"
set "CARGO_HOME=D:\path\to\cargo"
"D:\path\to\cargo\bin\cargo.exe" install rust-script --version <VERSION> --locked
```

For a bounded compile/install, track the process to a real exit code. Do not stop at `cargo install` success or `rust-script --version`; execute a script that proves embedded dependency resolution, compilation, cache creation, and runtime execution:

```rust
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! ```

use anyhow::Result;

fn main() -> Result<()> {
    println!("rust-script-ok");
    Ok(())
}
```

Run it with the explicit executable under the same initialized MSVC environment:

```cmd
"D:\\path\\to\\cargo\\bin\\rust-script.exe" --version
"D:\\path\\to\\cargo\\bin\\rust-script.exe" rust_script_check.rs
```

When launching the native Windows `rust-script.exe` from Git Bash/MSYS, prefer a native Windows absolute path for the script argument:

```bash
"$BIN/rust-script.exe" 'C:\\temp\\rust_script_check.rs'
```

Do not assume an MSYS temporary path such as `/tmp/tmp.x.rs` will be converted for this argument. If the native executable reports `could not find script`, convert the path first with `cygpath -w "$script"`, or create the temporary source under a known Windows directory and pass its native path. This is an argument-path interoperability issue; distinguish it from compilation or toolchain failure.

Acceptance requires the pinned version, expected script output, and exit code 0. Confirm registration with `cargo install --list`, then remove temporary `.cmd` and source files. Installation does not require changing global `PATH`; document the custom executable path and provide per-shell environment setup instead.

Keep Cargo's native single-file experiment distinct from `rust-script`: `cargo -Z script` may remain nightly-only even when stable Cargo displays the flag in `cargo -Z help`. The third-party `rust-script` executable is the reliable stable-toolchain path when its own end-to-end test passes.

## Exact-version caution

Pin the full toolchain string when reproducibility matters, for example:

```text
1.97.1-x86_64-pc-windows-msvc
```

Report both the release and commit/date from `rustc --version --verbose`; this distinguishes a genuinely pinned toolchain from whichever default toolchain happens to be on `PATH`.

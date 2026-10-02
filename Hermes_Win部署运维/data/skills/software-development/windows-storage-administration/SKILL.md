---
name: windows-storage-administration
description: Safely inspect and modify Windows disks, partitions, volumes, and drive letters from Hermes, especially when launched through MSYS/Git Bash. Covers privilege elevation, collision-free renaming, UAC handling, state verification, and rollback-aware execution.
---

# Windows Storage Administration

Use this skill when a task changes Windows drive letters, partitions, volumes, disk layouts, mount points, or related storage metadata. Treat these as privileged, stateful operations with a high risk of disrupting running applications.

## Operating Principles

1. Inspect before changing anything.
   - Enumerate disks, partitions, volumes, file systems, labels, sizes, and current drive letters.
   - Identify system, boot, recovery, reserved, internal data, and removable volumes.
   - Never infer a target from drive letters alone when disk and partition identity is available.
2. Establish the intended mapping explicitly.
   - Record the source identity as `DiskNumber + PartitionNumber` or a stable volume identifier.
   - Separate internal and removable media according to the user's stated policy.
   - Confirm that target letters are unique and do not collide with `C:`, recovery mounts, or currently assigned volumes.
3. Treat drive-letter changes as disruptive.
   - Warn that processes using old paths can fail during and after the operation.
   - Prefer a short, deterministic transaction with immediate post-change verification.
   - Do not change unrelated partitions or use destructive disk operations when only letters are requested.
4. Use an elevated process.
   - Storage cmdlets such as `Set-Partition` generally require Administrator rights.
   - Check elevation explicitly before mutation. If not elevated, launch a separate elevated PowerShell process with UAC and wait for its exit code.
   - A UAC timeout or a process that remains waiting is not evidence of success. Re-read the storage state.
5. Account for the MSYS/Git Bash boundary.
   - Do not place complex PowerShell in an inline `-Command` string when it contains `$variables`, loops, or nested quotes; MSYS and shell expansion can corrupt it before PowerShell parses it.
   - Write a `.ps1` file, then invoke it with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`.
   - Use `MSYS_NO_PATHCONV=1` and a native Windows path when invoking a Windows script from MSYS.
6. Avoid letter collisions with temporary letters.
   - Move each affected volume to unused temporary letters first, then assign final letters.
   - Choose temporary letters after inspecting current assignments; do not assume `W:`, `X:`, `Y:`, or `Z:` are free.
   - Apply the moves in a deterministic order and stop on the first failure.
7. Verify from an independent read operation.
   - Query `Get-Partition`, `Get-Volume`, and, when useful, `Get-Disk` after mutation.
   - Verify every target identity, letter, size, and expected media class.
   - Re-check that system and recovery partitions were untouched.
   - Report the actual resulting mapping and any incomplete step; never infer success from a command that merely started.

## Recommended Workflow

1. Capture a before snapshot to a file or structured output.
2. Check the current process is elevated. If not, prepare a script and request elevation.
3. Validate the requested mapping against the snapshot and reject ambiguity.
4. Select unused temporary letters and produce a reversible mapping.
5. Execute the temporary moves and final assignments in one elevated script with `$ErrorActionPreference = 'Stop'`.
6. Capture an after snapshot even if the script exits nonzero.
7. Compare before and after by stable partition identity, not by drive letter.
8. Report exact status, including whether UAC was accepted, declined, or timed out.

## Failure Handling

- If a storage cmdlet returns an access/privilege error, stop mutation, verify that no earlier move occurred, and rerun only after elevation is confirmed.
- If a script path fails under MSYS, diagnose path conversion before changing the storage logic. Use a native absolute path and `MSYS_NO_PATHCONV=1`.
- If UAC is waiting, do not issue repeated mutation attempts. Check for the elevation prompt/process and independently inspect the current mapping.
- If a partial move occurred, reconstruct the current state from disk/partition identity, then complete or reverse the mapping deliberately. Do not blindly rerun the original sequence.
- Keep generated scripts in a known workspace path and leave them available for user audit unless the user asks for cleanup.

## Supporting Detail

See `references/msys-uac-drive-letter-change.md` for the tested failure modes, command invocation patterns, and verification checklist.

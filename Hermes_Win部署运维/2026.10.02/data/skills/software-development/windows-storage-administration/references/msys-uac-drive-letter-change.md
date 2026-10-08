# MSYS, UAC, and Drive-Letter Changes

## Session-derived failure modes

### Inline PowerShell expansion
An inline command containing PowerShell variables and `foreach` was altered before PowerShell parsed it. The error appeared as a missing variable name in `foreach`, indicating that `$item` had been stripped or expanded by the invoking shell. Keep non-trivial PowerShell in a `.ps1` file.

### MSYS path conversion
Calling PowerShell with `/c/Users/.../script.ps1` produced a `-File` argument error. Invoke with a native Windows path while disabling MSYS conversion:

```bash
MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\<user>\workspace\script.ps1'
```

### Privilege and error 42012
`Set-Partition` returned StorageWMI error `42012` from a non-elevated PowerShell process. The operation stopped at the first temporary move. The observed partition mapping remained unchanged, but this must always be checked rather than assumed.

### UAC waiting
A wrapper using `Start-Process powershell.exe -Verb RunAs -Wait` can remain blocked while waiting for UAC interaction. A command timeout is an indeterminate result, not a success or failure signal. Inspect the process and query the partition mapping independently. Do not repeatedly submit the same mutation while an elevation request may still be pending.

## Safe invocation pattern

1. Write the complete mutation and verification logic to a `.ps1` file.
2. Make the script fail fast with `$ErrorActionPreference = 'Stop'`.
3. Start it elevated with `Start-Process -Verb RunAs -Wait -PassThru`, or run it from an already elevated PowerShell.
4. After the process returns or times out, run an independent read-only query.
5. Compare by `DiskNumber` and `PartitionNumber`, not only by drive letter.

## Verification query

```powershell
Get-Partition |
  Where-Object DriveLetter |
  Sort-Object DriveLetter |
  Select-Object DiskNumber, PartitionNumber, DriveLetter, Size
```

For a production workflow, also capture `Get-Disk` and `Get-Volume`, and record the before snapshot before any mutation.

## Important limitation

The session did not complete the requested reassignment because the storage cmdlet was not run in a confirmed elevated context. The durable lesson is the elevation and verification workflow, not the session's specific disk mapping.

# Field notes: Windows SMB printer cases

## Validated connection sequence

A reliable client-side sequence is:

1. Confirm ping and TCP 445.
2. Run unauthenticated `net view`; error 5 confirms the endpoint is reachable but requires credentials.
3. Remove only the target's stale `IPC$` session and Credential Manager entry.
4. Add the target credential and establish a persistent `IPC$` session.
5. Enumerate shares and copy the exact printer share name.
6. Add via `Add-Printer -ConnectionName`.
7. Verify the exact queue object, status, and driver.
8. Inventory same-model queues on old IPs; do not delete without authorization.
9. Delete any temporary script that contained a plaintext password.

## Evidence hierarchy

Do not treat one signal as conclusive. Strong combined evidence is:

- ping succeeds;
- TCP 445 is open;
- credentialed `net use` succeeds;
- `net view` lists the printer share;
- `Add-Printer` succeeds;
- `Get-Printer` shows the exact UNC connection as `Normal`;
- physical output is confirmed separately.

`Get-SmbConnection` can be empty after successful setup, so avoid using its absence alone to declare failure.

## Stale queues and application behavior

Multiple same-model UNC queues on different IPs can all display `Normal`, because that property does not prove the old server is current or that an application selected the intended queue. WPS and similar applications may cache a stale queue. Always give the user the exact current UNC path and enumerate old variants.

## UNC transport pitfall

When commands pass from Hermes through git-bash/MSYS to `cmd.exe` or PowerShell, UNC backslashes and nested quotes may be transformed. False error 67/1702 can result even with TCP 445 open. Write commands into a `.ps1` with the file API and execute it using `powershell.exe -File` before escalating to server changes.

## Credential hygiene

A temporary `.ps1` may need a password for unattended connection, but it must be deleted at the end. Do not quote the password in the completion message or save it in this reference. Prefer interactive secure input when practical.

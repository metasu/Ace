---
name: windows-network-printers
description: Diagnose, connect, verify, and clean up Windows LAN/SMB shared printers. Use for UNC printer paths, IP changes, SMB credential errors, stale printer entries, WPS selecting the wrong printer, or errors 5/53/67/86/1219/1326/1702/0x8007052e/0x800702e4.
---

# Windows Network Printers

Use this skill for Windows printers shared from another Windows host over SMB. The goal is not merely to add a queue: finish with a correctly identified target, an authenticated SMB path, a healthy printer connection, and—when the user permits—a real test print.

## Safety and operating rules

- Confirm the **current** server IP/hostname, printer share name, and account before changing anything. DHCP addresses and stale instructions are common.
- Never put a real password in documentation, chat summaries, durable skill files, or reusable scripts. A temporary generated `.ps1` may contain it only when required for execution; delete that script immediately afterward.
- Clean only the named target. Never use `net use * /delete` because it can disrupt unrelated business shares.
- Do not delete old printers or change the default printer without user authorization unless explicitly included in the request.
- Do not weaken security by enabling SMB1, insecure guest access, or disabling the firewall by default.
- The task is not complete merely because `Add-Printer` returns success. Verify queue state and, when authorized, actual output.

## Workflow

### 1. Identify the target

Record:

- Current server IP or hostname
- Server computer name when known
- Exact printer share name
- Server-local username
- Whether to set it as default
- Whether old same-model connections may be removed
- Whether a physical test page may be printed

If the user supplies only an IP and credentials, discover the share name after authentication rather than guessing it.

### 2. Use a `.ps1` file for Windows networking commands

Hermes terminal sessions on Windows may run through git-bash/MSYS. Inline UNC paths can be altered by quoting, slash conversion, or escape processing, producing false errors 67/1702. Write the complete PowerShell logic to a `.ps1` file with the file tool, then execute:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\probe.ps1"
```

A successful TCP 445 probe combined with stable inline `net use` error 67 is a strong reason to retry through a `.ps1` before changing the server.

### 3. Probe before authenticating

In the script:

1. Ping the target.
2. Probe TCP 445 with `System.Net.Sockets.TcpClient` or `Test-NetConnection`.
3. Run `cmd.exe /c "net view \\<target>"`.
4. Inspect target-specific existing SMB sessions and printers.

Interpretation:

- Ping/445 unavailable: stop and resolve network, host, or firewall reachability.
- 445 open plus error 5 / Access Denied: proceed with credentials.
- 445 open plus 67/1702: first rule out command transport corruption by using a `.ps1`; only then investigate server sharing/firewall.
- Error 53: path/host is unavailable.

### 4. Authenticate narrowly

Remove only a stale session and credential for the current target, then add the supplied credential and establish `IPC$`:

```powershell
cmd.exe /c "net use \\<target>\IPC$ /delete /y"
cmdkey.exe /delete:<target>
cmdkey.exe /add:<target> /user:<user> /pass:<password>
cmd.exe /c "net use \\<target>\IPC$ /user:<user> <password> /persistent:yes"
```

If the bare username is rejected, retry as `<SERVERNAME>\<user>`. A Windows account password is required, not a Windows Hello PIN.

Error guidance:

- 1219: a connection to that server already uses different credentials; enumerate and remove only target-specific sessions.
- 86/1326 or `0x8007052e`: authentication or account-format failure.
- `0x800702e4`: elevation is likely required, often for driver installation.

### 5. Discover and add the exact share

After authentication, run `net view \\<target>` and use the exact printer share name. Add it with:

```powershell
Add-Printer -ConnectionName '\\<target>\<share>'
```

If an existing queue is found, avoid adding a duplicate. If `Add-Printer` is unsuitable and the driver is already available, consider:

```powershell
rundll32 printui.dll,PrintUIEntry /in /n "\\<target>\<share>"
```

### 6. Verify without overclaiming

Check the newly added queue directly:

```powershell
Get-Printer -Name '\\<target>\<share>' |
  Format-List Name,Type,ComputerName,PortName,PrinterStatus,DriverName
```

Expected baseline: `Type=Connection` and `PrinterStatus=Normal`. Also inspect SMB state when available. Note that `Get-SmbConnection` output may be empty even after a successful add if the connection is no longer active; the authenticated `net use`, successful share enumeration, and printer object are stronger combined evidence than that command alone.

Do not claim successful physical printing unless a test page or user-confirmed document actually came out. With permission, send a test page:

```powershell
rundll32 printui.dll,PrintUIEntry /k /n "\\<target>\<share>"
```

### 7. Detect stale same-model entries

List all printers with the same model/share pattern and report old IPs. Applications such as WPS may cache and select a stale connection even when the new queue is healthy. Tell the user the exact UNC path to select.

Only after permission, remove stale entries. If `Remove-Printer` hangs for an offline connection, remove its matching per-user key under:

```text
HKCU:\Printers\Connections\,,<ip>,<share>
```

Then refresh the spooler only if appropriate and authorized; restarting it affects active print jobs and may require elevation.

### 8. Server-side escalation

If client-side `.ps1` testing confirms the problem is server-side, inspect on the sharing host with administrator rights:

- `net share`
- `Get-Printer` shared state and share name
- `LanmanServer` and `Spooler`
- Current network profile (Private/Public)
- Inbound `FPS-*` firewall rules

On localized Windows, prefer internal firewall rule names (`FPS-*`) rather than the English display group “File and Printer Sharing.” Limit rules to the trusted profile/subnet.

## Cleanup

Delete any temporary `.ps1` containing a password immediately after the operation, including on failure. Keep Credential Manager entries only when persistent reconnection was requested or is appropriate; otherwise remove the target credential and diagnostic `IPC$` session.

## Completion report

Report separately:

- Network/445 result
- Credential acceptance
- Exact discovered share
- Exact UNC printer path added
- Queue status and driver
- Whether default printer was changed
- Whether a physical test page was attempted and confirmed
- Any stale same-model entries left in place

Never expose the password in the report.

## Supporting files

- `references/field-notes.md` — durable case-derived pitfalls and evidence hierarchy.
- `scripts/probe-network-printer.ps1` — reusable password-free probe for reachability, shares, SMB sessions, and related queues.

param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [string]$PrinterPattern = '*'
)

$ErrorActionPreference = 'Continue'

Write-Output '=== Ping ==='
ping.exe -n 2 $Target

Write-Output '=== TCP 445 ==='
$client = New-Object System.Net.Sockets.TcpClient
$async = $client.BeginConnect($Target, 445, $null, $null)
if ($async.AsyncWaitHandle.WaitOne(3000) -and $client.Connected) {
    Write-Output '445 OPEN'
} else {
    Write-Output '445 CLOSED'
}
$client.Close()

Write-Output '=== Shares (may require prior authentication) ==='
cmd.exe /c "net view \\$Target"

Write-Output '=== SMB connections ==='
Get-SmbConnection -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerName -eq $Target } |
    Format-Table ServerName, ShareName, UserName, Dialect -AutoSize

Write-Output '=== Related printers ==='
Get-Printer -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ComputerName -eq $Target -or
        $_.Name -like "*$Target*" -or
        $_.Name -like $PrinterPattern
    } |
    Select-Object Name, Type, ComputerName, PortName, PrinterStatus, DriverName |
    Format-Table -AutoSize

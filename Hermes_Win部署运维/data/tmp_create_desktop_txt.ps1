$desktop = [Environment]::GetFolderPath('Desktop')
$path = Join-Path $desktop '新建空白文件.txt'
[System.IO.File]::Create($path).Dispose()
$item = Get-Item -LiteralPath $path
Write-Output ("PATH=" + $item.FullName)
Write-Output ("LENGTH=" + $item.Length)

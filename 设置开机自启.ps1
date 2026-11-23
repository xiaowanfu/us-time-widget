# 把「美国时间挂件」加入/移出开机启动项（当前用户，无需管理员）
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) '美国时间挂件.lnk'

if ($Remove) {
    if (Test-Path -LiteralPath $lnkPath) {
        Remove-Item -LiteralPath $lnkPath -Force
        Write-Host "已移除开机自启：$lnkPath" -ForegroundColor Yellow
    } else {
        Write-Host "没有找到自启快捷方式，无需移除。"
    }
    return
}

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnk.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $dir 'USClockWidget.ps1')
$lnk.WorkingDirectory = $dir
$lnk.WindowStyle = 7
$lnk.Description = '美国时间桌面挂件'
$lnk.Save()

Write-Host "已设置开机自启：$lnkPath" -ForegroundColor Green
Write-Host "下次登录 Windows 后会自动出现在屏幕右上角。"

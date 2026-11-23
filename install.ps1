# 一键安装：解除下载锁定 -> 建桌面快捷方式 -> 启动挂件
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# 1) 解除“来自 Internet”的锁定，避免以后每次启动都弹安全警告
Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# 2) 创建桌面快捷方式（直接调 powershell.exe，不经过 .bat，所以不会再弹提示）
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop '美国时间挂件.lnk'
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $dir 'launch.ps1')
$lnk.WorkingDirectory = $dir
if (Test-Path (Join-Path $dir 'widget.ico')) {
    $lnk.IconLocation = (Join-Path $dir 'widget.ico') + ',0'
}
$lnk.Description = '美国官方时间桌面挂件'
$lnk.Save()

# 3) 直接启动一次
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Start-Process -FilePath $ps -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', "`"$(Join-Path $dir 'launch.ps1')`""
) -WindowStyle Hidden

Start-Sleep -Seconds 6

[System.Windows.Forms.MessageBox]::Show(
    "安装完成！`r`n`r`n桌面已生成「美国时间挂件」图标，双击即可打开。`r`n`r`n" +
    "· 快捷键：Shift + Space  显示 / 隐藏`r`n" +
    "· 也可以单击托盘里的时钟小图标`r`n" +
    "· 右键卡片可以切换 24 小时制、透明度、位置`r`n`r`n" +
    "窗口位置在屏幕右上角。没看到的话，点右下角托盘区的图标。`r`n`r`n" +
    "如果挪动了文件夹位置，重新运行一次本安装程序即可。",
    '美国时间挂件 - 安装完成', 'OK', 'Information') | Out-Null

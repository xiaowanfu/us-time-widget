# 美国时间挂件启动器：启动后确认窗口是否真的出现，失败会弹框说明原因
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$dir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$widgetScript = Join-Path $dir 'USClockWidget.ps1'
$log = Join-Path $dir 'startup.log'
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class LauncherProbe {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);

    public static bool WidgetVisible()
    {
        bool found = false;
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            StringBuilder t = new StringBuilder(256);
            GetWindowText(h, t, 256);
            if (t.ToString() == "美国官方时间" && IsWindowVisible(h)) { found = true; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@

if (-not (Test-Path -LiteralPath $widgetScript)) {
    [System.Windows.Forms.MessageBox]::Show("找不到主程序：`n$widgetScript", '美国时间挂件', 'OK', 'Error') | Out-Null
    return
}

# 已经在运行就直接让它显示出来（主程序自己会处理单实例）
if ([LauncherProbe]::WidgetVisible()) {
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$widgetScript`"") -WindowStyle Hidden
    Start-Sleep -Milliseconds 1200
    if ([LauncherProbe]::WidgetVisible()) { return }
}

Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue

$psArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$widgetScript`"")
$proc = Start-Process -FilePath $exe -ArgumentList $psArgs -WindowStyle Hidden -PassThru -RedirectStandardError $log -RedirectStandardOutput (Join-Path $dir 'startup.out')

$ok = $false
for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Milliseconds 500
    if ([LauncherProbe]::WidgetVisible()) { $ok = $true; break }
    if ($proc.HasExited -and $i -gt 6) { break }
}

if (-not $ok) {
    $detail = ''
    foreach ($f in @($log, (Join-Path $dir 'startup.out'))) {
        if (Test-Path -LiteralPath $f) {
            $txt = Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue
            if ($txt) { $detail += $txt.Trim() + "`r`n" }
        }
    }
    if (-not $detail) { $detail = '没有捕获到错误输出（进程可能根本没启动，或被安全软件拦截）。' }
    if ($detail.Length -gt 900) { $detail = $detail.Substring($detail.Length - 900) }
    [System.Windows.Forms.MessageBox]::Show(
        "挂件没能启动。`r`n`r`n错误信息：`r`n$detail`r`n`r`n可以把这段发给我。",
        '美国时间挂件 - 启动失败', 'OK', 'Error') | Out-Null
}

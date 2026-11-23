# 停止正在运行的美国时间挂件（按窗口枚举定位进程，不依赖 WMI）
$ErrorActionPreference = 'SilentlyContinue'

Add-Type @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinScan {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);

    public static List<int> FindPids(out List<IntPtr> windows)
    {
        List<int> pids = new List<int>();
        List<IntPtr> wins = new List<IntPtr>();
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            StringBuilder t = new StringBuilder(256);
            StringBuilder c = new StringBuilder(256);
            GetWindowText(h, t, 256);
            GetClassName(h, c, 256);
            if (t.ToString() == "美国官方时间" || c.ToString() == "DshUsClockWidgetMsgWnd")
            {
                int pid = 0;
                GetWindowThreadProcessId(h, out pid);
                if (!pids.Contains(pid)) pids.Add(pid);
                wins.Add(h);
            }
            return true;
        }, IntPtr.Zero);
        windows = wins;
        return pids;
    }
}
"@

$wins = $null
$pids = [WinScan]::FindPids([ref]$wins)
if ($pids.Count -eq 0) {
    Write-Host "挂件当前没有在运行。" -ForegroundColor DarkGray
    return
}

# 先礼貌关闭（会正常保存位置、清理托盘图标）
foreach ($h in $wins) { [void][WinScan]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }
Start-Sleep -Milliseconds 1500

$wins2 = $null
$left = [WinScan]::FindPids([ref]$wins2)
foreach ($id in $left) {
    Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    Write-Host "已强制结束挂件 (PID $id)" -ForegroundColor Yellow
}
if ($left.Count -eq 0) { Write-Host "已关闭挂件。" -ForegroundColor Green }

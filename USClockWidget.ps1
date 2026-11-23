<#
    美国官方时间 · 桌面挂件
    - 时间 + 日期 + 近 3 个跨境电商节日倒计时
    - 无边框 / 透明圆角 / 置顶 / 可拖动
    - Ctrl+Space 显示/隐藏（底层键盘钩子，绕过输入法抢占；可在 settings.json 改）
#>
param(
    [string]$Preview,      # 传入 png 路径则只渲染预览图后退出
    [switch]$NoMutex
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$script:AppDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:SettingsPath = Join-Path $script:AppDir 'settings.json'
$script:Culture = [System.Globalization.CultureInfo]::GetCultureInfo('zh-CN')
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

# 美国官方时间 = 联邦政府所在地华盛顿特区时间（东部时间），自动跟随夏令时
$script:TZ = 'Eastern Standard Time'

$script:MsgClass = 'DshUsClockWidgetMsgWnd'

Add-Type @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public class HotkeyWindow : IDisposable
{
    private const int WM_HOTKEY = 0x0312;

    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX
    {
        public uint cbSize;
        public uint style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClassEx(ref WNDCLASSEX wc);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowExW(uint exStyle, string cls, string name, uint style,
        int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowW(string cls, string title);
    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    private WndProcDelegate _proc;
    private IntPtr _hwnd;

    public event Action HotkeyPressed;
    public event Action ShowRequested;

    public IntPtr Handle { get { return _hwnd; } }

    public HotkeyWindow(string className)
    {
        _proc = new WndProcDelegate(WndProcImpl);
        WNDCLASSEX wc = new WNDCLASSEX();
        wc.cbSize = (uint)Marshal.SizeOf(typeof(WNDCLASSEX));
        wc.lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_proc);
        wc.hInstance = GetModuleHandle(null);
        wc.lpszClassName = className;
        RegisterClassEx(ref wc);

        // WS_EX_TOOLWINDOW：普通隐藏窗口（0 尺寸、不带 WS_VISIBLE）
        _hwnd = CreateWindowExW(0x00000080, className, "USClockWidgetMsg", 0, 0, 0, 0, 0,
            IntPtr.Zero, IntPtr.Zero, wc.hInstance, IntPtr.Zero);
        if (_hwnd == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    public bool RegisterHotkey(uint mods, uint vk)
    {
        return RegisterHotKey(_hwnd, 0xBEEF, mods, vk);
    }

    private IntPtr WndProcImpl(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_HOTKEY)
        {
            Action h = HotkeyPressed;
            if (h != null) h();
            return IntPtr.Zero;
        }
        if (msg == 0x8001)
        {
            Action s = ShowRequested;
            if (s != null) s();
            return IntPtr.Zero;
        }
        return DefWindowProc(hWnd, msg, wParam, lParam);
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    public static IntPtr FindWidgetWindow(string title)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l)
        {
            StringBuilder sb = new StringBuilder(256);
            GetWindowTextW(h, sb, 256);
            if (sb.ToString() == title) { found = h; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static bool IsVisible(IntPtr h) { return IsWindowVisible(h); }

    public void Dispose()
    {
        if (_hwnd != IntPtr.Zero)
        {
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
        GC.SuppressFinalize(this);
    }
}
"@

$script:HotkeyId = 0xBEEF

# ---------- 单实例：已经开着就把旧窗口叫出来 ----------
$script:ShowEventName = 'Local\USClockWidget_ShowEvent'
if (-not $NoMutex) {
    $existing = [HotkeyWindow]::FindWidgetWindow('美国官方时间')
    if ($existing -ne [IntPtr]::Zero) {
        # 通知已在运行的实例显示出来
        try {
            $ev = [System.Threading.EventWaitHandle]::OpenExisting($script:ShowEventName)
            [void]$ev.Set()
            $ev.Dispose()
        } catch { }
        Start-Sleep -Milliseconds 1500
        if ([HotkeyWindow]::IsVisible($existing)) { return }
        # 旧实例没响应（卡死的残留进程），继续启动新的
    }
}
$script:ShowEvent = $null
try {
    $script:ShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $script:ShowEventName)
} catch {
    # 命名事件被别的进程（可能是不同权限级别的残留实例）占用时，忽略即可
}

# ---------- 设置 ----------
$script:Settings = [pscustomobject]@{
    Left = $null; Top = $null; H24 = $false; Topmost = $true; Opacity = 1.0; Hotkey = 'Shift+Space'
}

function Load-Settings {
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try {
            $saved = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $saved.PSObject.Properties) {
                if ($script:Settings.PSObject.Properties.Name -contains $p.Name -and $null -ne $p.Value) {
                    $script:Settings.($p.Name) = $p.Value
                }
            }
        } catch { }
    }
}

function Save-Settings {
    try { $script:Settings | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8 } catch { }
}

# 排查用：设置环境变量 USCLOCK_LOG=1 会写 debug.log
function Log([string]$msg) {
    if (-not $env:USCLOCK_LOG) { return }
    try { Add-Content -LiteralPath (Join-Path $script:AppDir 'debug.log') -Value ('{0:HH:mm:ss.fff} {1}' -f (Get-Date), $msg) -Encoding UTF8 } catch { }
}

Load-Settings

# ---------- 界面 ----------
[xml]$xamlXml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="美国官方时间" Width="272" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize"
        FontFamily="Microsoft YaHei UI" TextOptions.TextFormattingMode="Display"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Grid x:Name="Root" Margin="16">
    <Border x:Name="Card" CornerRadius="16">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#FA1A2432" Offset="0"/>
          <GradientStop Color="#FA0A0F18" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.BorderBrush>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#33FFFFFF" Offset="0"/>
          <GradientStop Color="#0DFFFFFF" Offset="1"/>
        </LinearGradientBrush>
      </Border.BorderBrush>
      <Border.BorderThickness>1</Border.BorderThickness>
      <Border.Effect>
        <DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.55" Color="#FF000000"/>
      </Border.Effect>
      <Grid>
        <Rectangle Height="3" VerticalAlignment="Top" Margin="20,0,20,0" RadiusX="2" RadiusY="2">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
              <GradientStop Color="#FF4C9AFF" Offset="0"/>
              <GradientStop Color="#FF9D7BFF" Offset="0.5"/>
              <GradientStop Color="#FFF472B6" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>
        <StackPanel Margin="16,14,16,12">
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
            <TextBlock x:Name="BigTime" Text="--:--:--" FontFamily="Consolas" FontSize="34"
                       Foreground="#FFF4F8FF" VerticalAlignment="Bottom"/>
            <TextBlock x:Name="BigAmpm" Text="" FontSize="11.5" Foreground="#FF7E90A8"
                       VerticalAlignment="Bottom" Margin="6,0,0,6"/>
          </StackPanel>
          <TextBlock x:Name="DateText" Text="" Margin="1,2,0,0" FontSize="12"
                     Foreground="#FF8FA3C0" HorizontalAlignment="Center"/>
          <TextBlock x:Name="TipText" Text="" Margin="0,6,0,0" FontSize="10.5"
                     Foreground="#FFE0A64B" HorizontalAlignment="Center" TextWrapping="Wrap"
                     MaxWidth="215" Visibility="Collapsed"/>

          <Rectangle Height="1" Fill="#1FFFFFFF" Margin="2,11,2,9"/>

          <TextBlock Text="近期跨境节点" FontSize="9.5" Foreground="#FF5E7188"
                     HorizontalAlignment="Center" Margin="0,0,0,7"/>

          <Grid x:Name="F1" Margin="2,0,2,6">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="F1Name" Grid.Column="0" Text="" FontSize="12" Foreground="#FFC6D4E6"/>
            <TextBlock x:Name="F1Date" Grid.Column="1" Text="" FontSize="10" Foreground="#FF5E7188"
                       Margin="0,0,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="F1Days" Grid.Column="2" Text="" FontSize="11" Foreground="#FFF5A623"
                       TextAlignment="Right" MinWidth="52"/>
          </Grid>

          <Grid x:Name="F2" Margin="2,0,2,6">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="F2Name" Grid.Column="0" Text="" FontSize="12" Foreground="#FFC6D4E6"/>
            <TextBlock x:Name="F2Date" Grid.Column="1" Text="" FontSize="10" Foreground="#FF5E7188"
                       Margin="0,0,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="F2Days" Grid.Column="2" Text="" FontSize="11" Foreground="#FFF5A623"
                       TextAlignment="Right" MinWidth="52"/>
          </Grid>

          <Grid x:Name="F3" Margin="2,0,2,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="F3Name" Grid.Column="0" Text="" FontSize="12" Foreground="#FFC6D4E6"/>
            <TextBlock x:Name="F3Date" Grid.Column="1" Text="" FontSize="10" Foreground="#FF5E7188"
                       Margin="0,0,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="F3Days" Grid.Column="2" Text="" FontSize="11" Foreground="#FFF5A623"
                       TextAlignment="Right" MinWidth="52"/>
          </Grid>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xamlXml
$win = [System.Windows.Markup.XamlReader]::Load($reader)

$ui = @{}
foreach ($n in 'Card', 'BigTime', 'BigAmpm', 'DateText', 'TipText',
    'F1Name', 'F1Date', 'F1Days', 'F2Name', 'F2Date', 'F2Days', 'F3Name', 'F3Date', 'F3Days') {
    $ui[$n] = $win.FindName($n)
    if ($null -eq $ui[$n]) { throw "界面元素缺失: $n" }
}

$win.Topmost = [bool]$script:Settings.Topmost
$win.Opacity = [double]$script:Settings.Opacity

# ---------- 跨境电商节日 ----------
function Get-Easter([int]$year) {
    $a = $year % 19
    $b = [math]::Floor($year / 100)
    $c = $year % 100
    $d = [math]::Floor($b / 4)
    $e = $b % 4
    $f = [math]::Floor(($b + 8) / 25)
    $g = [math]::Floor(($b - $f + 1) / 3)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [math]::Floor($c / 4)
    $k = $c % 4
    $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    $m = [math]::Floor(($a + 11 * $h + 22 * $l) / 451)
    $month = [int][math]::Floor(($h + $l - 7 * $m + 114) / 31)
    $day = [int]((($h + $l - 7 * $m + 114) % 31) + 1)
    return New-Object DateTime($year, $month, $day)
}

function Get-NthWeekday([int]$year, [int]$month, [DayOfWeek]$dow, [int]$n) {
    if ($n -gt 0) {
        $first = New-Object DateTime($year, $month, 1)
        $offset = ([int]$dow - [int]$first.DayOfWeek + 7) % 7
        return $first.AddDays($offset + 7 * ($n - 1))
    }
    $last = (New-Object DateTime($year, $month, 1)).AddMonths(1).AddDays(-1)
    $offset = ([int]$last.DayOfWeek - [int]$dow + 7) % 7
    return $last.AddDays(-$offset)
}

# 跨境电商营销日历（不是美国传统节日表：含双11、返校季、黑五网一、节礼日等）
$script:Festivals = @(
    [pscustomobject]@{ Name = '元旦';   Rule = 'fixed'; Month = 1;  Day = 1 }
    [pscustomobject]@{ Name = '情人节'; Rule = 'fixed'; Month = 2;  Day = 14 }
    [pscustomobject]@{ Name = '复活节'; Rule = 'easter' }
    [pscustomobject]@{ Name = '母亲节'; Rule = 'nth'; Month = 5;  Dow = 'Sunday';   N = 2 }
    [pscustomobject]@{ Name = '纪念日'; Rule = 'nth'; Month = 5;  Dow = 'Monday';   N = -1 }
    [pscustomobject]@{ Name = '父亲节'; Rule = 'nth'; Month = 6;  Dow = 'Sunday';   N = 3 }
    [pscustomobject]@{ Name = '独立日'; Rule = 'fixed'; Month = 7;  Day = 4 }
    [pscustomobject]@{ Name = '返校季'; Rule = 'fixed'; Month = 8;  Day = 15 }
    [pscustomobject]@{ Name = '劳动节'; Rule = 'nth'; Month = 9;  Dow = 'Monday';   N = 1 }
    [pscustomobject]@{ Name = '万圣节'; Rule = 'fixed'; Month = 10; Day = 31 }
    [pscustomobject]@{ Name = '双11';  Rule = 'fixed'; Month = 11; Day = 11 }
    [pscustomobject]@{ Name = '黑五';   Rule = 'thanks+1' }
    [pscustomobject]@{ Name = '网一';   Rule = 'thanks+4' }
    [pscustomobject]@{ Name = '圣诞';   Rule = 'fixed'; Month = 12; Day = 25 }
    [pscustomobject]@{ Name = '节礼日'; Rule = 'fixed'; Month = 12; Day = 26 }
)

function Get-FestivalDate([object]$f, [int]$year) {
    switch ($f.Rule) {
        'fixed' { return New-Object DateTime($year, $f.Month, $f.Day) }
        'easter' { return Get-Easter $year }
        'nth' { return Get-NthWeekday $year $f.Month ([DayOfWeek]$f.Dow) $f.N }
        'thanks+1' { return (Get-NthWeekday $year 11 ([DayOfWeek]'Thursday') 4).AddDays(1) }
        'thanks+4' { return (Get-NthWeekday $year 11 ([DayOfWeek]'Thursday') 4).AddDays(4) }
    }
    return $null
}

function Get-NextFestivals([DateTime]$today, [int]$count = 3) {
    $list = New-Object System.Collections.ArrayList
    foreach ($f in $script:Festivals) {
        for ($y = $today.Year; $y -le $today.Year + 1; $y++) {
            $d = Get-FestivalDate $f $y
            if ($d -and $d.Date -ge $today.Date) {
                [void]$list.Add([pscustomobject]@{
                        Name = $f.Name
                        Date = $d.Date
                        Days = ($d.Date - $today.Date).Days
                    })
                break
            }
        }
    }
    return @($list | Sort-Object Date, Name | Select-Object -First $count)
}

function Update-Festivals([DateTime]$today) {
    $items = Get-NextFestivals $today 3
    for ($i = 0; $i -lt 3; $i++) {
        $n = $i + 1
        if ($i -lt $items.Count) {
            $it = $items[$i]
            $ui["F${n}Name"].Text = $it.Name
            $ui["F${n}Date"].Text = $it.Date.ToString('M/d', $script:Culture)
            if ($it.Days -eq 0) {
                $ui["F${n}Days"].Text = '就是今天'
                $ui["F${n}Days"].Foreground = '#FFFF6B6B'
            } elseif ($it.Days -eq 1) {
                $ui["F${n}Days"].Text = '明天'
                $ui["F${n}Days"].Foreground = '#FFFF6B6B'
            } else {
                $ui["F${n}Days"].Text = "剩 $($it.Days) 天"
                if ($it.Days -le 7) { $ui["F${n}Days"].Foreground = '#FFF5A623' }
                else { $ui["F${n}Days"].Foreground = '#FF7E93AC' }
            }
        } else {
            $ui["F${n}Name"].Text = ''
            $ui["F${n}Date"].Text = ''
            $ui["F${n}Days"].Text = ''
        }
    }
}

# ---------- 时间 ----------
$script:TzInfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($script:TZ)
$script:LastFestivalDate = $null

function Update-Clock {
    $t = [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $script:TzInfo)
    if ([bool]$script:Settings.H24) {
        $ui['BigTime'].Text = $t.ToString('HH:mm:ss')
        $ui['BigAmpm'].Text = ''
    } else {
        $ui['BigTime'].Text = $t.ToString('hh:mm:ss')
        $ui['BigAmpm'].Text = $t.ToString('tt', $script:Invariant)
    }
    $ui['DateText'].Text = $t.ToString('M月d日 ddd', $script:Culture)

    if ($script:LastFestivalDate -ne $t.Date) {
        $script:LastFestivalDate = $t.Date
        Update-Festivals $t.Date
    }
}

Update-Clock

# ---------- 提示 ----------
function Show-Tip([string]$text, [int]$seconds = 6) {
    $ui['TipText'].Text = $text
    $ui['TipText'].Visibility = 'Visible'
    if ($script:TipTimer) { $script:TipTimer.Stop() }
    $script:TipTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:TipTimer.Interval = [TimeSpan]::FromSeconds($seconds)
    $script:TipTimer.Add_Tick({
            $script:TipTimer.Stop()
            $ui['TipText'].Visibility = 'Collapsed'
        })
    $script:TipTimer.Start()
}

# ---------- 显示 / 隐藏 ----------
function Show-Widget {
    $win.Show()
    $win.Topmost = [bool]$script:Settings.Topmost
    $win.Activate()
}

function Hide-Widget { $win.Hide() }

function Toggle-Widget {
    if ($win.IsVisible) { Hide-Widget } else { Show-Widget }
}

# ---------- 快捷键 ----------
function Convert-Hotkey([string]$text) {
    $mods = 0
    $parts = @($text -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -lt 2) { throw '快捷键格式应为 修饰键+按键，例如 Ctrl+Space' }
    $keyName = $parts[-1]
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        switch ($parts[$i].ToLower()) {
            'ctrl' { $mods = $mods -bor 0x0002 }
            'control' { $mods = $mods -bor 0x0002 }
            'alt' { $mods = $mods -bor 0x0001 }
            'shift' { $mods = $mods -bor 0x0004 }
            'win' { $mods = $mods -bor 0x0008 }
            default { throw "不支持的修饰键: $($parts[$i])" }
        }
    }
    $conv = New-Object System.Windows.Input.KeyConverter
    $key = $conv.ConvertFromString($keyName)
    if ($key -isnot [System.Windows.Input.Key]) { throw "不支持的按键: $keyName" }
    $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
    if ($vk -eq 0) { throw "不支持的按键: $keyName" }
    [pscustomobject]@{ Mods = $mods; Vk = $vk }
}

$script:HotkeyHwnd = [IntPtr]::Zero
$script:MsgWin = $null

function Setup-Hotkey {
    $want = [string]$script:Settings.Hotkey
    $candidates = @($want, 'Shift+Space', 'Ctrl+Shift+Space', 'Alt+Shift+Space', 'Ctrl+Alt+Space') | Select-Object -Unique
    foreach ($c in $candidates) {
        try {
            $hk = Convert-Hotkey $c
            if ($script:MsgWin.RegisterHotkey($hk.Mods, $hk.Vk)) {
                $script:ActiveHotkey = $c
                Log "热键已注册: $c"
                if ($c -ne $want) { Show-Tip "「$want」已被占用，改用 $c" }
                return
            }
        } catch {
            if ($c -eq $want) { Show-Tip "「$want」无效，改用备用快捷键" }
        }
    }
    Show-Tip '快捷键不可用，请点托盘图标或右键菜单显示/隐藏'
}

# ---------- 托盘图标 ----------
$script:Tray = $null
function Setup-Tray {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $script:Tray = New-Object System.Windows.Forms.NotifyIcon
        $script:Tray.Icon = [System.Drawing.SystemIcons]::Application
        $script:Tray.Text = '美国官方时间（单击显示/隐藏）'
        $script:Tray.Visible = $true

        $cm = New-Object System.Windows.Forms.ContextMenuStrip
        $miToggle = New-Object System.Windows.Forms.ToolStripMenuItem('显示 / 隐藏')
        $miToggle.Add_Click({ Toggle-Widget })
        $miExit = New-Object System.Windows.Forms.ToolStripMenuItem('退出挂件')
        $miExit.Add_Click({ $win.Close() })
        [void]$cm.Items.Add($miToggle)
        [void]$cm.Items.Add($miExit)
        $script:Tray.ContextMenuStrip = $cm

        $script:Tray.Add_MouseClick({
                param($s, $e)
                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Toggle-Widget }
            })
    } catch {
        Log "托盘图标创建失败: $($_.Exception.Message)"
    }
}

# ---------- 右键菜单 ----------
function New-MenuItem([string]$header, [scriptblock]$onClick, [bool]$checkable = $false, [bool]$checked = $false) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header
    if ($checkable) { $mi.IsCheckable = $true; $mi.IsChecked = $checked }
    if ($onClick) { $mi.Add_Click($onClick) }
    return $mi
}

$menu = New-Object System.Windows.Controls.ContextMenu
$menu.FontFamily = 'Microsoft YaHei UI'
$menu.FontSize = 12

$menu.Items.Add((New-MenuItem '24 小时制' {
            param($s, $e)
            $script:Settings.H24 = [bool]$s.IsChecked
            Update-Clock
            Save-Settings
        } $true ([bool]$script:Settings.H24))) | Out-Null

$menu.Items.Add((New-MenuItem '始终置顶' {
            param($s, $e)
            $win.Topmost = [bool]$s.IsChecked
            $script:Settings.Topmost = $win.Topmost
            Save-Settings
        } $true ([bool]$script:Settings.Topmost))) | Out-Null

$opacityMenu = New-Object System.Windows.Controls.MenuItem
$opacityMenu.Header = '不透明度'
$opacityHandler = {
    param($s, $e)
    $win.Opacity = [double]$s.Tag
    $script:Settings.Opacity = $win.Opacity
    Save-Settings
}
foreach ($lv in @(
        @{ T = '100%'; V = 1.0 }
        @{ T = '90%'; V = 0.9 }
        @{ T = '80%'; V = 0.8 }
        @{ T = '65%'; V = 0.65 }
    )) {
    $item = New-MenuItem $lv.T $opacityHandler
    $item.Tag = $lv.V
    $opacityMenu.Items.Add($item) | Out-Null
}
$menu.Items.Add($opacityMenu) | Out-Null

$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

$hideItem = New-MenuItem '隐藏挂件' { Hide-Widget }
$hideItem.InputGestureText = [string]$script:Settings.Hotkey
$menu.Items.Add($hideItem) | Out-Null

$menu.Items.Add((New-MenuItem '回到屏幕右上角' {
            $wa = [System.Windows.SystemParameters]::WorkArea
            $win.Left = $wa.Right - $win.ActualWidth - 24
            $win.Top = $wa.Top + 24
            Save-Settings
        })) | Out-Null

$menu.Items.Add((New-MenuItem '退出挂件' { $win.Close() })) | Out-Null

$win.ContextMenu = $menu

# ---------- 拖动 / 双击隐藏 ----------
$win.Add_MouseLeftButtonDown({
        param($s, $e)
        if ($e.ClickCount -eq 2) { Hide-Widget; return }
        try { $win.DragMove() } catch { }
    })

# ---------- 位置 ----------
function Restore-Position {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $left = $script:Settings.Left
    $top = $script:Settings.Top
    if ($null -eq $left -or $null -eq $top) {
        $win.Left = $wa.Right - $win.ActualWidth - 24
        $win.Top = $wa.Top + 24
        return
    }
    $onScreen = ($left -ge $wa.Left - 50) -and ($left -le $wa.Right - 80) -and
                ($top -ge $wa.Top - 20) -and ($top -le $wa.Bottom - 50)
    if (-not $onScreen) {
        $win.Left = $wa.Right - $win.ActualWidth - 24
        $win.Top = $wa.Top + 24
    } else {
        $win.Left = [double]$left
        $win.Top = [double]$top
    }
}

$win.Add_Loaded({ Restore-Position })

$win.Add_Closed({
        $script:Settings.Left = $win.Left
        $script:Settings.Top = $win.Top
        Save-Settings
        if ($script:MsgWin) { $script:MsgWin.Dispose() }
        if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() }
        try { if ($script:Mutex) { $script:Mutex.ReleaseMutex() } } catch { }
    })

# ---------- 预览渲染 ----------
if ($Preview) {
    $win.Show()
    Update-Clock
    $win.UpdateLayout()

    $w = [int][math]::Ceiling($win.ActualWidth)
    $h = [int][math]::Ceiling($win.ActualHeight)
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($win.Content)

    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Preview)
    $enc.Save($fs)
    $fs.Close()

    $win.Close()
    Write-Output "preview: $Preview ($w x $h)"
    return
}

# ---------- 消息窗口 / 热键 / 托盘 ----------
$script:MsgWin = New-Object HotkeyWindow($script:MsgClass)
$script:HotkeyHwnd = $script:MsgWin.Handle
$script:MsgWin.add_HotkeyPressed({ Toggle-Widget })
$script:MsgWin.add_ShowRequested({ Show-Widget })
Setup-Hotkey
Setup-Tray

# ---------- 运行 ----------
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({ Update-Clock })
$timer.Start()

# 再次双击启动器时，通过命名事件把窗口叫出来
$wake = New-Object System.Windows.Threading.DispatcherTimer
$wake.Interval = [TimeSpan]::FromMilliseconds(700)
$wake.Add_Tick({
        if ($script:ShowEvent -and $script:ShowEvent.WaitOne(0)) { Show-Widget }
    })
$wake.Start()

$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
try { $app.Run($win) | Out-Null } finally { [Environment]::Exit(0) }

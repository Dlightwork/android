param(
    [switch]$NoElevate
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $NoElevate -and -not (Test-IsAdmin)) {
    $argLine = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`" -NoElevate"
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argLine
    exit 0
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) {
    $argLine = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`" -NoElevate"
    Start-Process -FilePath "powershell.exe" -ArgumentList $argLine
    exit 0
}

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class GlassInterop
{
    [StructLayout(LayoutKind.Sequential)]
    public struct AccentPolicy
    {
        public int AccentState;
        public int AccentFlags;
        public int GradientColor;
        public int AnimationId;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WindowCompositionAttributeData
    {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }

    [DllImport("user32.dll")]
    public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    public static void EnableAcrylic(IntPtr hwnd)
    {
        // ACCENT_ENABLE_ACRYLICBLURBEHIND = 4
        var accent = new AccentPolicy();
        accent.AccentState = 4;
        // AABBGGRR
        accent.GradientColor = unchecked((int)0xCCF6F7FF);
        accent.AccentFlags = 2;

        int accentStructSize = Marshal.SizeOf(accent);
        IntPtr accentPtr = Marshal.AllocHGlobal(accentStructSize);
        try
        {
            Marshal.StructureToPtr(accent, accentPtr, false);
            var data = new WindowCompositionAttributeData();
            // WCA_ACCENT_POLICY = 19
            data.Attribute = 19;
            data.SizeOfData = accentStructSize;
            data.Data = accentPtr;
            SetWindowCompositionAttribute(hwnd, ref data);
        }
        finally
        {
            Marshal.FreeHGlobal(accentPtr);
        }
    }
}
"@

$Root = Split-Path -Parent $PSCommandPath
$EnginePath = Join-Path $Root "winws2.exe"
$RunnerPath = Join-Path $Root "tools\run-winws2-preset.ps1"
$BasePreset = Join-Path $Root "presets\all_tcp_udp_multisplit_sni.args"

if (-not (Test-Path -LiteralPath $EnginePath)) {
    [System.Windows.MessageBox]::Show("Не найден файл winws2.exe в папке проекта.","Zapret GUI",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    exit 1
}
if (-not (Test-Path -LiteralPath $RunnerPath)) {
    [System.Windows.MessageBox]::Show("Не найден файл tools\run-winws2-preset.ps1.","Zapret GUI",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    exit 1
}
if (-not (Test-Path -LiteralPath $BasePreset)) {
    [System.Windows.MessageBox]::Show("Не найден файл presets\all_tcp_udp_multisplit_sni.args.","Zapret GUI",[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error) | Out-Null
    exit 1
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Zapret Glass UI"
        Width="1040"
        Height="700"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="#01000000"
        FontFamily="Segoe UI">
    <Window.Resources>
        <DropShadowEffect x:Key="SoftShadow" BlurRadius="24" ShadowDepth="0" Opacity="0.25" Color="#202A44"/>
        <Style x:Key="GlassBtn" TargetType="Button">
            <Setter Property="Margin" Value="0,0,10,10"/>
            <Setter Property="Padding" Value="14,10"/>
            <Setter Property="Foreground" Value="#10203A"/>
            <Setter Property="Background" Value="#CCFFFFFF"/>
            <Setter Property="BorderBrush" Value="#80FFFFFF"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border CornerRadius="14"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#E8FFFFFF"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#B5E4FF"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Border x:Name="GlassRoot"
                CornerRadius="24"
                BorderThickness="1"
                BorderBrush="#88FFFFFF"
                Effect="{StaticResource SoftShadow}">
            <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                    <GradientStop Color="#66FFFFFF" Offset="0.0"/>
                    <GradientStop Color="#33DCEBFF" Offset="0.55"/>
                    <GradientStop Color="#44FFFFFF" Offset="1.0"/>
                </LinearGradientBrush>
            </Border.Background>

            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="68"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="34"/>
                </Grid.RowDefinitions>

                <Border x:Name="TopBar" Grid.Row="0" Background="#20FFFFFF" CornerRadius="24,24,0,0">
                    <Grid Margin="16,0,10,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Orientation="Vertical" VerticalAlignment="Center">
                            <TextBlock Text="Zapret Control Center" FontSize="20" FontWeight="SemiBold" Foreground="#14223D"/>
                            <TextBlock Text="winws2 + Lua + Bin + Lists" FontSize="12" Foreground="#4A5D81"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                            <Button x:Name="BtnMin" Width="34" Height="28" Margin="0,0,8,0" Style="{StaticResource GlassBtn}" Padding="0">−</Button>
                            <Button x:Name="BtnClose" Width="34" Height="28" Style="{StaticResource GlassBtn}" Padding="0">×</Button>
                        </StackPanel>
                    </Grid>
                </Border>

                <Grid Grid.Row="1" Margin="18">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="2.1*"/>
                        <ColumnDefinition Width="1.1*"/>
                    </Grid.ColumnDefinitions>

                    <Grid Grid.Column="0">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <WrapPanel Grid.Row="0">
                            <Button x:Name="BtnStartMultisplit" Style="{StaticResource GlassBtn}" MinWidth="220">Start: ALL TCP/UDP multisplit</Button>
                            <Button x:Name="BtnStartStrong" Style="{StaticResource GlassBtn}" MinWidth="220">Start: STRONG profile</Button>
                            <Button x:Name="BtnStop" Style="{StaticResource GlassBtn}" MinWidth="140" Background="#FFEFEFEF">Stop</Button>
                            <Button x:Name="BtnDiag" Style="{StaticResource GlassBtn}" MinWidth="160">Roblox diagnostics</Button>
                        </WrapPanel>

                        <Border Grid.Row="1" Margin="0,10,0,0" CornerRadius="16" Background="#55FFFFFF" BorderBrush="#70FFFFFF" BorderThickness="1">
                            <Grid Margin="12">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <TextBlock Text="Runtime Log" FontSize="13" FontWeight="SemiBold" Foreground="#31466B" Margin="0,0,0,8"/>
                                <TextBox x:Name="LogBox"
                                         Grid.Row="1"
                                         IsReadOnly="True"
                                         TextWrapping="Wrap"
                                         VerticalScrollBarVisibility="Auto"
                                         Background="#20FFFFFF"
                                         BorderThickness="0"
                                         Foreground="#132845"
                                         FontFamily="Consolas"
                                         FontSize="12"/>
                            </Grid>
                        </Border>
                    </Grid>

                    <StackPanel Grid.Column="1" Margin="14,0,0,0">
                        <Border CornerRadius="16" Background="#55FFFFFF" BorderBrush="#70FFFFFF" BorderThickness="1" Margin="0,0,0,10">
                            <StackPanel Margin="14">
                                <TextBlock Text="Mode Options" FontWeight="SemiBold" FontSize="14" Foreground="#31466B" Margin="0,0,0,8"/>
                                <CheckBox x:Name="ChkRobloxSupplement" Content="Enable Roblox supplement" IsChecked="True" Margin="0,0,0,6"/>
                                <CheckBox x:Name="ChkAutoLists" Content="Use auto host/ip lists" IsChecked="True" Margin="0,0,0,6"/>
                                <CheckBox x:Name="ChkHiddenRunner" Content="Run helper hidden" IsChecked="True"/>
                            </StackPanel>
                        </Border>

                        <Border CornerRadius="16" Background="#55FFFFFF" BorderBrush="#70FFFFFF" BorderThickness="1" Margin="0,0,0,10">
                            <StackPanel Margin="14">
                                <TextBlock Text="Status" FontWeight="SemiBold" FontSize="14" Foreground="#31466B" Margin="0,0,0,10"/>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <Ellipse x:Name="StatusDot" Width="12" Height="12" Fill="#B0B0B0" Margin="0,0,8,0"/>
                                    <TextBlock x:Name="StatusText" Text="Idle" Foreground="#203554"/>
                                </StackPanel>
                                <TextBlock x:Name="ModeText" Text="Mode: -" Foreground="#425D85"/>
                                <TextBlock x:Name="ProcText" Text="Runner PID: -" Foreground="#425D85" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border CornerRadius="16" Background="#55FFFFFF" BorderBrush="#70FFFFFF" BorderThickness="1">
                            <StackPanel Margin="14">
                                <TextBlock Text="Quick Actions" FontWeight="SemiBold" FontSize="14" Foreground="#31466B" Margin="0,0,0,10"/>
                                <Button x:Name="BtnOpenFolder" Style="{StaticResource GlassBtn}" Margin="0,0,0,8">Open project folder</Button>
                                <Button x:Name="BtnOpenPreset" Style="{StaticResource GlassBtn}" Margin="0,0,0,8">Open base preset</Button>
                                <Button x:Name="BtnOpenLists" Style="{StaticResource GlassBtn}" Margin="0,0,0,0">Open lists folder</Button>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Grid>

                <TextBlock Grid.Row="2" Margin="16,0,16,8" Foreground="#53688F" FontSize="11"
                           Text="Tip: run only one mode at a time. Stop before switching profiles."/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$TopBar = $window.FindName("TopBar")
$BtnMin = $window.FindName("BtnMin")
$BtnClose = $window.FindName("BtnClose")
$BtnStartMultisplit = $window.FindName("BtnStartMultisplit")
$BtnStartStrong = $window.FindName("BtnStartStrong")
$BtnStop = $window.FindName("BtnStop")
$BtnDiag = $window.FindName("BtnDiag")
$BtnOpenFolder = $window.FindName("BtnOpenFolder")
$BtnOpenPreset = $window.FindName("BtnOpenPreset")
$BtnOpenLists = $window.FindName("BtnOpenLists")
$ChkRobloxSupplement = $window.FindName("ChkRobloxSupplement")
$ChkAutoLists = $window.FindName("ChkAutoLists")
$ChkHiddenRunner = $window.FindName("ChkHiddenRunner")
$LogBox = $window.FindName("LogBox")
$StatusDot = $window.FindName("StatusDot")
$StatusText = $window.FindName("StatusText")
$ModeText = $window.FindName("ModeText")
$ProcText = $window.FindName("ProcText")

$script:currentRunner = $null
$script:currentMode = "-"
$script:tempFiles = New-Object System.Collections.Generic.List[string]

function Add-Log {
    param([string]$Text)
    $time = Get-Date -Format "HH:mm:ss"
    $LogBox.AppendText("[$time] $Text`r`n")
    $LogBox.ScrollToEnd()
}

function Set-UiStatus {
    param(
        [string]$Text,
        [string]$Mode,
        [string]$ColorHex = "#B0B0B0"
    )
    $StatusText.Text = $Text
    $ModeText.Text = "Mode: $Mode"
    $StatusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($ColorHex)
    if ($script:currentRunner -and -not $script:currentRunner.HasExited) {
        $ProcText.Text = "Runner PID: $($script:currentRunner.Id)"
    } else {
        $ProcText.Text = "Runner PID: -"
    }
}

function Resolve-RobloxLists {
    $host = Join-Path $Root "lists\list-roblox.txt"
    if (-not (Test-Path -LiteralPath $host)) { $host = Join-Path $Root "list-roblox.txt" }
    if (-not (Test-Path -LiteralPath $host)) { $host = Join-Path $Root "lists\roblox_domains.txt" }
    if (-not (Test-Path -LiteralPath $host)) { $host = Join-Path $Root "roblox_domains.txt" }

    $ip = Join-Path $Root "lists\ipset-roblox.txt"
    if (-not (Test-Path -LiteralPath $ip)) { $ip = Join-Path $Root "ipset-roblox.txt" }
    if (-not (Test-Path -LiteralPath $ip)) { $ip = Join-Path $Root "lists\roblox_ips.txt" }
    if (-not (Test-Path -LiteralPath $ip)) { $ip = Join-Path $Root "roblox_ips.txt" }

    [PSCustomObject]@{
        Host = $host
        Ip   = $ip
        Ok   = (Test-Path -LiteralPath $host) -and (Test-Path -LiteralPath $ip)
    }
}

function Build-AutoLists {
    $autoHost = Join-Path $Root "lists\_auto_hostlist.txt"
    $autoIp = Join-Path $Root "lists\_auto_ipset.txt"

    $skip = @(
        "selected_bin.txt",
        "test_out.txt",
        "error.txt",
        "help.txt",
        "cmakelists.txt",
        "service_config.txt",
        "_auto_hostlist.txt",
        "_auto_ipset.txt"
    )

    Set-Content -LiteralPath $autoHost -Value "" -Encoding ASCII
    Set-Content -LiteralPath $autoIp -Value "" -Encoding ASCII

    $hostCount = 0
    $ipCount = 0
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $dirs = @((Join-Path $Root "lists"), $Root)

    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -File -Filter "*.txt" | ForEach-Object {
            $name = $_.Name
            if ($name -like "*.Zone.Identifier") { return }
            if ($skip -contains $name.ToLowerInvariant()) { return }
            if ($dir -eq $Root -and (Test-Path -LiteralPath (Join-Path $Root ("lists\" + $name)))) { return }
            if (-not $seen.Add($name.ToLowerInvariant())) { return }

            $isIp = ($_.BaseName -match "ipset|_ips")
            if ($isIp) {
                Add-Content -LiteralPath $autoIp -Value (Get-Content -LiteralPath $_.FullName -Raw) -Encoding ASCII
                Add-Content -LiteralPath $autoIp -Value "`r`n" -Encoding ASCII
                $ipCount++
            } else {
                Add-Content -LiteralPath $autoHost -Value (Get-Content -LiteralPath $_.FullName -Raw) -Encoding ASCII
                Add-Content -LiteralPath $autoHost -Value "`r`n" -Encoding ASCII
                $hostCount++
            }
        }
    }

    [PSCustomObject]@{
        HostPath = $autoHost
        IpPath   = $autoIp
        HostCount = $hostCount
        IpCount = $ipCount
        HostOk = (Test-Path -LiteralPath $autoHost) -and ((Get-Item -LiteralPath $autoHost).Length -gt 0)
        IpOk = (Test-Path -LiteralPath $autoIp) -and ((Get-Item -LiteralPath $autoIp).Length -gt 0)
    }
}

function New-AppendPresetForMode {
    param([ValidateSet("multisplit","strong")] [string]$Mode)

    if (-not $ChkRobloxSupplement.IsChecked) {
        return $null
    }

    $lists = Resolve-RobloxLists
    if ($ChkAutoLists.IsChecked) {
        $auto = Build-AutoLists
        if ($auto.HostOk) { $lists.Host = $auto.HostPath }
        if ($auto.IpOk) { $lists.Ip = $auto.IpPath }
        $lists.Ok = (Test-Path -LiteralPath $lists.Host) -and (Test-Path -LiteralPath $lists.Ip)
        Add-Log "Auto lists updated: host=$($auto.HostCount), ip=$($auto.IpCount)"
    }

    if (-not $lists.Ok) {
        Add-Log "Roblox lists are missing. Supplement block skipped."
        return $null
    }

    $append = Join-Path $env:TEMP ("zapret_gui_" + $Mode + "_" + [Guid]::NewGuid().ToString("N") + ".args")
    if ($Mode -eq "multisplit") {
        @(
            "--new"
            "--filter-udp=49152-65535"
            "--hostlist=$($lists.Host)"
            "--ipset=$($lists.Ip)"
            "--out-range=-d8"
            "--payload=all"
            "--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10"
        ) | Set-Content -LiteralPath $append -Encoding ASCII
    } else {
        @(
            "--new"
            "--filter-udp=49152-65535"
            "--hostlist=$($lists.Host)"
            "--ipset=$($lists.Ip)"
            "--out-range=-d10"
            "--payload=all"
            "--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=12"
            "--new"
            "--filter-udp=49152-65535"
            "--ipset=$($lists.Ip)"
            "--out-range=-d10"
            "--payload=all"
            "--lua-desync=fake:blob=fake_quic:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=12"
            "--new"
            "--filter-tcp=443,1024-65535"
            "--hostlist=$($lists.Host)"
            "--ipset=$($lists.Ip)"
            "--out-range=-d8"
            "--lua-desync=send:repeats=2"
            "--lua-desync=syndata:blob=tls_google"
            "--lua-desync=tls_multisplit_sni:seqovl=652:seqovl_pattern=tls_google"
        ) | Set-Content -LiteralPath $append -Encoding ASCII
    }

    [void]$script:tempFiles.Add($append)
    Add-Log "Roblox supplement enabled: $($lists.Host) + $($lists.Ip)"
    return $append
}

function Stop-Current {
    try {
        if ($script:currentRunner -and -not $script:currentRunner.HasExited) {
            Stop-Process -Id $script:currentRunner.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    & taskkill /f /im winws2.exe *> $null
    & taskkill /f /im winws.exe *> $null

    foreach ($f in @($script:tempFiles)) {
        try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch {}
    }
    $script:tempFiles.Clear()

    $script:currentRunner = $null
    $script:currentMode = "-"
    Set-UiStatus -Text "Stopped" -Mode "-" -ColorHex "#B0B0B0"
    Add-Log "All running profiles stopped."
}

function Start-Profile {
    param([ValidateSet("multisplit","strong")] [string]$Mode)

    Stop-Current

    $append = New-AppendPresetForMode -Mode $Mode
    $presetArg = $BasePreset
    if ($append) { $presetArg = "$BasePreset;$append" }

    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $RunnerPath,
        "-EnginePath", $EnginePath,
        "-BaseDir", $Root,
        "-PresetFile", $presetArg
    )

    $windowStyle = if ($ChkHiddenRunner.IsChecked) { "Hidden" } else { "Normal" }
    $script:currentRunner = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WorkingDirectory $Root -PassThru -WindowStyle $windowStyle
    $script:currentMode = $Mode
    Set-UiStatus -Text "Running" -Mode $Mode -ColorHex "#53C66A"
    Add-Log "Started mode '$Mode' (runner PID: $($script:currentRunner.Id))."
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1.5)
$timer.Add_Tick({
    if ($script:currentRunner -and $script:currentRunner.HasExited) {
        Add-Log "Runner exited. Exit code: $($script:currentRunner.ExitCode)"
        foreach ($f in @($script:tempFiles)) {
            try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch {}
        }
        $script:tempFiles.Clear()
        $script:currentRunner = $null
        $script:currentMode = "-"
        Set-UiStatus -Text "Idle" -Mode "-" -ColorHex "#B0B0B0"
    }
})
$timer.Start()

$window.Add_SourceInitialized({
    try {
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        [GlassInterop]::EnableAcrylic($hwnd)
    } catch {}
})

$TopBar.Add_MouseLeftButtonDown({
    if ($_.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        $window.DragMove()
    }
})
$BtnMin.Add_Click({ $window.WindowState = "Minimized" })
$BtnClose.Add_Click({
    Stop-Current
    $window.Close()
})

$BtnStartMultisplit.Add_Click({ Start-Profile -Mode "multisplit" })
$BtnStartStrong.Add_Click({ Start-Profile -Mode "strong" })
$BtnStop.Add_Click({ Stop-Current })
$BtnDiag.Add_Click({
    $diag = Join-Path $Root "check_roblox_mode.bat"
    if (Test-Path -LiteralPath $diag) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$diag`"" -WorkingDirectory $Root
        Add-Log "Roblox diagnostics started."
    } else {
        Add-Log "check_roblox_mode.bat not found."
    }
})

$BtnOpenFolder.Add_Click({ Start-Process explorer.exe $Root })
$BtnOpenPreset.Add_Click({ Start-Process notepad.exe $BasePreset })
$BtnOpenLists.Add_Click({
    $lists = Join-Path $Root "lists"
    if (Test-Path -LiteralPath $lists) { Start-Process explorer.exe $lists }
})

$window.Add_Closing({
    $timer.Stop()
    Stop-Current
})

Add-Log "GUI ready. Select a profile to run."
Add-Log "Engine: $EnginePath"
Set-UiStatus -Text "Idle" -Mode "-" -ColorHex "#B0B0B0"

[void]$window.ShowDialog()

#Requires -Version 5.1
<#
===============================================================================
Script: WsusManagementGui.ps1
Author: Tony Tran, ISSO, Classified Computing, GA-ASI
Version: derived from metadata.json (see Get-WsusAppVersion in WsusConfig)
===============================================================================
.SYNOPSIS
    WSUS Manager GUI - Modern WPF interface for WSUS management
.DESCRIPTION
    Portable GUI for managing WSUS servers with SQL Express.
    Features: Dashboard, Health Score, Diagnostics, Online Sync, Import/Export, History, Notifications
#>

param(
    [switch]$E2EStartupProbe,
    [ValidateRange(3, 120)][int]$E2EStartupProbeSeconds = 12,
    [string]$E2EResultPath
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

#region DPI Awareness - Enable crisp rendering on high-DPI displays
try {
    Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class DpiAwareness {
            [DllImport("shcore.dll")]
            public static extern int SetProcessDpiAwareness(int awareness);

            [DllImport("user32.dll")]
            public static extern bool SetProcessDPIAware();

            public static void Enable() {
                try {
                    // Try Windows 8.1+ per-monitor DPI awareness
                    SetProcessDpiAwareness(2); // PROCESS_PER_MONITOR_DPI_AWARE
                } catch {
                    try {
                        // Fall back to Windows Vista+ system DPI awareness
                        SetProcessDPIAware();
                    } catch { $null = $_.Exception.Message }
                }
            }
        }
"@ -ErrorAction SilentlyContinue
    [DpiAwareness]::Enable()
} catch {
    $null = $_.Exception.Message
}
#endregion

# AppVersion is set AFTER modules load below (line ~310). The early assignment
# here used to fall back to '4.0.5' when Get-WsusAppVersion was not yet imported,
# which produced stale "=== Starting v4.0.5 ===" banners on real builds.
$script:AppVersion = $null
$script:StartupTime = Get-Date

#region Script Path & Settings
$script:ScriptRoot = $null
$exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ($exePath -and $exePath -notmatch 'powershell\.exe$|pwsh\.exe$') {
    $script:ScriptRoot = Split-Path -Parent $exePath
} elseif ($PSScriptRoot) {
    $script:ScriptRoot = $PSScriptRoot
} else {
    $script:ScriptRoot = (Get-Location).Path
}

$script:SettingsFile = Join-Path $env:APPDATA "WsusManager\settings.json"
$script:ContentPath = "C:\WSUS"
$script:SqlInstance = ".\SQLEXPRESS"
$script:ExportRoot = "C:\"
$script:InstallPath = "C:\WSUS\SQLDB"
$script:SaUser = "sa"
$script:LogDir = "C:\WSUS\Logs"
# Use shared daily log file - all operations go to one log
$script:LogPath = Join-Path $script:LogDir "WsusOperations_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:ServerMode = "Online"
$script:ServerModeOverride = $null   # set to "Online" or "Air-Gap" to lock mode manually
$script:RefreshInProgress = $false
$script:CurrentProcess = $null
$script:OperationRunning = $false
$script:E2EStartupProbe = $E2EStartupProbe.IsPresent
$script:E2EStartupProbeSeconds = $E2EStartupProbeSeconds
$script:E2EResultPath = $E2EResultPath
$script:E2EPopupEvents = New-Object System.Collections.Generic.List[object]
$script:E2EProbeCompleted = $false
# Event subscription tracking for proper cleanup (prevents duplicates/leaks)
$script:OutputEventJob = $null
$script:ErrorEventJob = $null
$script:ExitEventJob = $null
$script:OpCheckTimer = $null
# Popup deduplication cache (prevents repeated noisy dialogs)
$script:PopupHistory = @{}
# Deduplication tracking - prevents same line appearing multiple times
$script:RecentLines = @{}
# Live Terminal Mode - launches operations in visible console window
$script:LiveTerminalMode = $true
$script:ForceEmbeddedMode = $false
$script:NotificationsEnabled = $true  # Show notifications when operations complete
$script:NotificationBeep = $false     # Beep on completion
# Theme: Dark mode only (light theme not implemented -- remove this comment when adding theme support)
$script:TrayMinimize = $false         # Minimize to system tray
$script:HistoryEnabled = $true        # Track operation history
$script:LegacyDefaultSyncProducts = @("Windows 11", "Windows Server 2019", "Microsoft Edge", "Microsoft Defender Antivirus", "Microsoft Defender for Endpoint", "Office 2016", "SQL Server 2022", "Security Essentials", "Microsoft 365 Apps", "Exchange Server 2019")
$script:DefaultSyncProducts = @("Windows 11", "Windows Server 2019", ".NET Framework", "Microsoft Edge", "Microsoft Defender Antivirus", "Microsoft Defender for Endpoint", "Office 2016", "SQL Server 2022", "Security Essentials", "Exchange Server 2019", "Visual Studio 2022")
$script:SyncProducts = @($script:DefaultSyncProducts)

function ConvertTo-WsusSyncProducts {
    param([string[]]$Products)

    $normalized = @(
        @($Products) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Select-Object -Unique
    )

    if ($normalized.Count -eq 0) {
        return @($script:DefaultSyncProducts)
    }

    $isLegacyDefault = (
        $normalized.Count -eq $script:LegacyDefaultSyncProducts.Count -and
        @($script:LegacyDefaultSyncProducts | Where-Object { $_ -notin $normalized }).Count -eq 0 -and
        @($normalized | Where-Object { $_ -notin $script:LegacyDefaultSyncProducts }).Count -eq 0
    )

    if ($isLegacyDefault) {
        return @($script:DefaultSyncProducts)
    }

    return $normalized
}

function Test-WsusSelectedProductTitle {
    param(
        [string]$SelectedProduct,
        [string]$AvailableTitle
    )

    # Loose substring/regex match so user defaults survive the
    # Server/WSUS renaming quirks ("Microsoft Defender Antivirus" default vs
    # WSUS's "Microsoft Defender Antimalware Platform", "Visual Studio 2022"
    # default vs "Visual Studio 2022 LTSC", etc.).
    switch -Regex ($SelectedProduct) {
        '^\s*\.NET Framework\s*$'          { return ($AvailableTitle -match '(?i)\.NET Framework') }
        '^Visual Studio 2022$'             { return ($AvailableTitle -match '(?i)\bVisual Studio 2022\b') }
        '^Microsoft Defender Antivirus$'   { return ($AvailableTitle -match '(?i)Defender.*Antivirus|Antimalware Platform') }
        '^Microsoft Defender for Endpoint$' { return ($AvailableTitle -match '(?i)Defender for Endpoint') }
        '^Office 2016$'                    { return ($AvailableTitle -match '(?i)\bOffice 2016\b') }
        '^SQL Server 2022$'                { return ($AvailableTitle -match '(?i)SQL Server (2022|2019|2017|2016)') }
        '^Security Essentials$'             { return ($AvailableTitle -match '(?i)\bSecurity Essentials\b') }
        '^Microsoft 365 Apps$'              { return ($AvailableTitle -match '(?i)\b(Microsoft 365 Apps|Office 365)\b') }
        '^Exchange Server 2019$'           { return ($AvailableTitle -match '(?i)Exchange Server 2019') }
        '^Windows 11$'                      { return ($AvailableTitle -match '(?i)Windows 11') }
        '^Windows Server 2019$'             { return ($AvailableTitle -match '(?i)Windows Server 2019') }
        default                            { return ($AvailableTitle -eq $SelectedProduct) }
    }
}
function Resolve-WsusBrandingAssetPath {
    param([Parameter(Mandatory)][string]$FileName)

    $searchRoots = @(
        $script:ScriptRoot,
        (Split-Path -Parent $script:ScriptRoot),
        (Join-Path $script:ScriptRoot 'Assets\Branding'),
        (Join-Path (Split-Path -Parent $script:ScriptRoot) 'Assets\Branding')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($root in $searchRoots) {
        $candidate = Join-Path $root $FileName
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}


function Write-Log { param([string]$Msg)
    try {
        if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
        "[$(Get-Date -Format 'HH:mm:ss')] $Msg" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch { $null = $_.Exception.Message }
}

function Initialize-E2EStartupProbe {
    if (-not $script:E2EStartupProbe) { return }

    if ([string]::IsNullOrWhiteSpace($script:E2EResultPath)) {
        $probeFileName = "WsusStartupProbe-$([Guid]::NewGuid().ToString('N')).json"
        $script:E2EResultPath = Join-Path ([System.IO.Path]::GetTempPath()) $probeFileName
    }
}

function Write-E2EStartupProbeResult {
    param(
        [string]$Status,
        [string]$Reason,
        [string]$FatalError = ""
    )

    if (-not $script:E2EStartupProbe -or $script:E2EProbeCompleted) { return }

    try {
        $popupEvents = if ($script:E2EPopupEvents.PSObject.Methods['ToArray']) { @($script:E2EPopupEvents.ToArray()) } else { @($script:E2EPopupEvents) }
        $result = New-WsusGuiStartupProbeResult -Status $Status -Reason $Reason -FatalError $FatalError -StartupProbeSeconds $script:E2EStartupProbeSeconds -ResultPath $script:E2EResultPath -PopupEvents $popupEvents
        Write-WsusGuiStartupProbeResult -Result $result -ResultPath $script:E2EResultPath
        Write-Log "E2E startup probe result written: $script:E2EResultPath"
    } catch {
        Write-Log "Failed to write E2E startup probe result: $($_.Exception.Message)"
    } finally {
        $script:E2EProbeCompleted = $true
    }
}

Initialize-E2EStartupProbe

function Import-WsusSettings {
    try {
        if (Test-Path $script:SettingsFile) {
            $s = Get-Content $script:SettingsFile -Raw | ConvertFrom-Json
            if ($s.ContentPath) { $script:ContentPath = $s.ContentPath }
            if ($s.SqlInstance) { $script:SqlInstance = $s.SqlInstance }
            if ($s.ExportRoot) { $script:ExportRoot = $s.ExportRoot }
            if ($s.ServerMode) { $script:ServerMode = $s.ServerMode }
            if ($null -ne $s.LiveTerminalMode) { $script:LiveTerminalMode = $s.LiveTerminalMode }
            if ($null -ne $s.NotificationsEnabled) { $script:NotificationsEnabled = $s.NotificationsEnabled }
            if ($null -ne $s.NotificationBeep) { $script:NotificationBeep = $s.NotificationBeep }
            if ($null -ne $s.TrayMinimize) { $script:TrayMinimize = $s.TrayMinimize }
            if ($null -ne $s.HistoryEnabled) { $script:HistoryEnabled = $s.HistoryEnabled }
            if ($null -ne $s.SyncProducts) { $script:SyncProducts = ConvertTo-WsusSyncProducts -Products @($s.SyncProducts) }
        }
    } catch {
        Write-Log "Failed to load settings: $_"
        $script:SettingsCorrupt = $true
    }
}
$script:SyncProducts = ConvertTo-WsusSyncProducts -Products $script:SyncProducts


function Save-Settings {
    try {
        $dir = Split-Path $script:SettingsFile -Parent
        if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        @{ ContentPath=$script:ContentPath; SqlInstance=$script:SqlInstance; ExportRoot=$script:ExportRoot; ServerMode=$script:ServerMode; LiveTerminalMode=$script:LiveTerminalMode; NotificationsEnabled=$script:NotificationsEnabled; NotificationBeep=$script:NotificationBeep; TrayMinimize=$script:TrayMinimize; HistoryEnabled=$script:HistoryEnabled; SyncProducts=@(ConvertTo-WsusSyncProducts -Products $script:SyncProducts) } |
            ConvertTo-Json | Set-Content $script:SettingsFile -Encoding UTF8
    } catch { Write-Log "Failed to save settings: $_" }
}
Import-WsusSettings

#region Import Additional Modules
$script:ModulesDir = $null
$moduleLocations = @($script:ScriptRoot, (Split-Path -Parent $script:ScriptRoot -ErrorAction SilentlyContinue), $PSScriptRoot) |
    Where-Object { $_ } | ForEach-Object { Join-Path $_ "Modules" }
foreach ($loc in $moduleLocations) {
    if (Test-Path $loc) { $script:ModulesDir = $loc; break }
}
if ($script:ModulesDir) {
    # Bypass execution policy for this process so UNC-path modules load without signing requirement
    try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch { $null = $_.Exception.Message }

    foreach ($mod in @("WsusUtilities","WsusConfig","WsusDatabase","WsusServices","WsusFirewall","WsusPermissions","WsusAutoDetection","WsusDiagnosticResult","WsusGuiShell","WsusStartupProbe","WsusOperationCompletion","WsusHostEnvironment","WsusRepairPlan","WsusHealth","WsusDialogs","WsusOperationPlan","WsusProvisioning","WsusOperationRunner","WsusHistory","WsusNotification","WsusTrending","WsusDashboardViewModel")) {
        $modPath = Join-Path $script:ModulesDir "$mod.psm1"
        if (Test-Path $modPath) {
            try { Import-Module $modPath -Force -DisableNameChecking -ErrorAction Stop }
            catch { Write-Log "Failed to load module ${mod}: $_" }
        }
    }
    # Re-establish utility exports after modules that import WsusUtilities privately with -Force.
    $utilitiesPath = Join-Path $script:ModulesDir "WsusUtilities.psm1"
    if (Test-Path $utilitiesPath) {
        try { Import-Module $utilitiesPath -Force -DisableNameChecking -ErrorAction Stop }
        catch { Write-Log "Failed to reload WsusUtilities exports: $_" }
    }
}

# Resolve the canonical app version AFTER modules load (was set to $null at the top
# of the script because Get-WsusAppVersion isn't imported until now).
if (Get-Command Get-WsusAppVersion -ErrorAction SilentlyContinue) {
    try { $script:AppVersion = Get-WsusAppVersion } catch { Write-Log "Get-WsusAppVersion failed: $_" }
}

if (Get-Command Get-WsusRuntimeConfig -ErrorAction SilentlyContinue) {
    try {
        $script:RuntimeConfig = Get-WsusRuntimeConfig
        if (Get-Command Get-WsusAppDataPath -ErrorAction SilentlyContinue) {
            $script:SettingsFile = Get-WsusAppDataPath -FileName 'settings.json'
        }
        $script:ContentPath = $script:RuntimeConfig.ContentPath
        $script:SqlInstance = $script:RuntimeConfig.SqlInstance
        $script:ExportRoot = $script:RuntimeConfig.DefaultExportPath
        $script:LogDir = $script:RuntimeConfig.LogPath
        $script:LogPath = Join-Path $script:LogDir "WsusOperations_$(Get-Date -Format 'yyyy-MM-dd').log"
        $script:InstallPath = Join-Path $script:ContentPath 'SQLDB'
    } catch {
        Write-Log "Runtime config initialization failed in GUI: $($_.Exception.Message)"
    }
}

# Re-establish GUI's file-based Write-Log after module imports.

# Configure a dialog to auto-size and stay within screen bounds.
# Removes fixed Height, sets SizeToContent=Height, MaxHeight=90% of screen,
# and allows vertical resize as fallback for very small screens.
function Set-DialogAutoFit {
    param([Parameter(Mandatory)][System.Windows.Window]$Window)
    $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight
    $Window.SizeToContent = [System.Windows.SizeToContent]::Height
    $Window.MaxHeight = [math]::Floor($screenH * 0.9)
    $Window.ResizeMode = "CanResizeWithGrip"
    $Window.MinHeight = 200
}
# WsusUtilities.psm1 exports its own Write-Log (stdout-only) which shadows
# the GUI's version defined earlier. The GUI needs file-based logging so
# that log messages persist to C:\WSUS\Logs even when no console is attached.
function Write-Log { param([string]$Msg)
    try {
        if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
        "[$(Get-Date -Format 'HH:mm:ss')] $Msg" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch { $null = $_.Exception.Message }
}
#endregion

Write-Log (New-WsusGuiLifecycleLogEntry -Event Starting -AppVersion $script:AppVersion)
#endregion

#region Security & Admin Check
function Get-EscapedPath { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    return $Path -replace "'", "''"
}

function Get-SqlCmdPath {
    # Return cached result if already found
    if ($script:CachedSqlCmdPath) { return $script:CachedSqlCmdPath }
    # Search common sqlcmd.exe locations (ODBC 18, 17, and legacy paths)
    $sqlcmdPaths = @(
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\170\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\150\Tools\Binn\sqlcmd.exe"
    )
    $script:CachedSqlCmdPath = $sqlcmdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    return $script:CachedSqlCmdPath
}

function Test-SafePath { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '[`$;|&<>"%]') { return $false }
    # Accept both local paths (C:\) and UNC paths (\\server\share or \\server\share$)
    # UNC pattern: \\server\share where share can include $ for admin shares
    if ($Path -notmatch '^([A-Za-z]:\\|\\\\[A-Za-z0-9_.-]+\\[A-Za-z0-9_.$-]+)') { return $false }
    return $true
}

$script:IsAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    $script:IsAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { Write-Log "Admin check failed: $_" }
#endregion

#region Console Window Helpers for Live Terminal
# P/Invoke for keystrokes and window positioning
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ConsoleWindowHelper {
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    public const uint WM_KEYDOWN = 0x0100;
    public const uint WM_KEYUP = 0x0101;
    public const int VK_RETURN = 0x0D;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;

    public static void SendEnter(IntPtr hWnd) {
        if (hWnd != IntPtr.Zero) {
            PostMessage(hWnd, WM_KEYDOWN, VK_RETURN, 0);
            PostMessage(hWnd, WM_KEYUP, VK_RETURN, 0);
        }
    }

    public static void PositionWindow(IntPtr hWnd, int x, int y, int width, int height) {
        if (hWnd != IntPtr.Zero) {
            MoveWindow(hWnd, x, y, width, height, true);
        }
    }
}
"@ -ErrorAction SilentlyContinue

$script:KeystrokeTimer = $null
$script:StdinFlushTimer = $null
#endregion

#region XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WSUS Manager" Height="800" Width="1000" MinHeight="650" MinWidth="850"
        WindowStartupLocation="CenterScreen" Background="#0D1117"
        FontFamily="Segoe UI"
        AutomationProperties.AutomationId="WsusManagerMainWindow">
    <Window.Resources>
        <SolidColorBrush x:Key="BgDark" Color="#0D1117"/>
        <SolidColorBrush x:Key="BgSidebar" Color="#161B22"/>
        <SolidColorBrush x:Key="BgCard" Color="#21262D"/>
        <SolidColorBrush x:Key="Border" Color="#30363D"/>
        <SolidColorBrush x:Key="Blue" Color="#58A6FF"/>
        <SolidColorBrush x:Key="Green" Color="#3FB950"/>
        <SolidColorBrush x:Key="Orange" Color="#D29922"/>
        <SolidColorBrush x:Key="Red" Color="#F85149"/>
        <SolidColorBrush x:Key="Text1" Color="#E6EDF3"/>
        <SolidColorBrush x:Key="Text2" Color="#8B949E"/>
        <SolidColorBrush x:Key="Text3" Color="#6E7681"/>
        <SolidColorBrush x:Key="TextDisabled" Color="#6E7681"/>

        <!-- Focus indicator for keyboard navigation (accessibility) -->
                <Style x:Key="FocusVisual">
            <Setter Property="Control.Template">
                <Setter.Value>
                    <ControlTemplate>
                        <Border BorderBrush="#58A6FF" BorderThickness="1" CornerRadius="4" Margin="-2" SnapsToDevicePixels="True"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NavBtn" TargetType="Button">
        <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource Text2}"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="4" Margin="4,0">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#21262D"/>
                                <Setter Property="Foreground" Value="{StaticResource Text1}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="Btn" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource Blue}"/>
            <Setter Property="Foreground" Value="{StaticResource Text1}"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Background" Value="#30363D"/>
                                <Setter Property="Foreground" Value="{StaticResource TextDisabled}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BtnSec" TargetType="Button" BasedOn="{StaticResource Btn}">
        <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
            <Setter Property="Background" Value="{StaticResource BgCard}"/>
            <Setter Property="Foreground" Value="{StaticResource Text1}"/>
            <Setter Property="FontWeight" Value="Normal"/>
        </Style>

        <Style x:Key="BtnGreen" TargetType="Button" BasedOn="{StaticResource Btn}">
        <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
            <Setter Property="Background" Value="{StaticResource Green}"/>
        </Style>

        <Style x:Key="BtnRed" TargetType="Button" BasedOn="{StaticResource Btn}">
        <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
            <Setter Property="Background" Value="{StaticResource Red}"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="180"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Background="{StaticResource BgSidebar}">
            <DockPanel>
                <StackPanel DockPanel.Dock="Top" Margin="12,16,12,0">
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                        <Image x:Name="SidebarLogo" Width="32" Height="32" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="WSUS Manager" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}"/>
                            <TextBlock x:Name="VersionLabel" Text="v..." FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                        </StackPanel>
                    </StackPanel>

                </StackPanel>

                <StackPanel DockPanel.Dock="Bottom" Margin="4,0,4,12">
                    <Button x:Name="BtnHistory" Content="☰ History" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnHelp" Content="? Help" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnSettings" Content="⚙ Settings" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnAbout" Content="ⓘ About" Style="{StaticResource NavBtn}"/>
                </StackPanel>

                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
                    <StackPanel>
                        <Button x:Name="BtnDashboard" Content="◉ Dashboard" Style="{StaticResource NavBtn}" Background="#21262D" Foreground="{StaticResource Text1}"/>

                        <TextBlock Text="SETUP" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,16,0,4"/>
                        <Button x:Name="BtnInstall" Content="▶ Install WSUS" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnFixSqlLogin" Content="[+] Fix SQL Login" Style="{StaticResource NavBtn}" ToolTip="Add current user as sysadmin to SQL Express"/>
                        <Button x:Name="BtnRestore" Content="↻ Restore DB" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnCreateGpo" Content="☰ Create GPO" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="MAINTENANCE" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,16,0,4"/>
                        <Button x:Name="BtnMaintenance" Content="↻ Online Sync" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnSchedule" Content="⌛ Schedule Task" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnCleanup" Content="✧ Deep Cleanup" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnTransfer" Content="⇄ Robocopy" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="DIAGNOSTICS" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,16,0,4"/>
                        <Button x:Name="BtnDiagnostics" Content="◎ Deep Diagnostics" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnReset" Content="↺ Reset Content" Style="{StaticResource NavBtn}" ToolTip="Re-verify all downloaded content files against the database"/>
                    </StackPanel>
                </ScrollViewer>
            </DockPanel>
        </Border>

        <!-- Main Content -->
        <Grid Grid.Column="1" Margin="20,16">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <DockPanel Margin="0,0,0,12">
                <Border x:Name="InternetStatusBorder" DockPanel.Dock="Right" Background="{StaticResource BgCard}" CornerRadius="4" Padding="8,4" Cursor="Hand">
                    <Border.ToolTip>Click to toggle Online/Offline mode manually</Border.ToolTip>
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Ellipse x:Name="InternetStatusDot" Width="8" Height="8" Fill="{StaticResource Red}" Margin="0,0,8,0"/>
                        <TextBlock x:Name="InternetStatusText" Text="Offline" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource Text2}"/>
                    </StackPanel>
                </Border>
                <TextBlock x:Name="PageTitle" Text="Dashboard" FontSize="20" FontWeight="Bold" Foreground="{StaticResource Text1}" VerticalAlignment="Center"/>
            </DockPanel>

            <!-- Dashboard Panel -->
            <Grid x:Name="DashboardPanel" AutomationProperties.AutomationId="DashboardPanel" Grid.Row="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Status Cards -->
                <UniformGrid Rows="1" Margin="0,0,0,16">
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card1Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Blue}"/>
                            <StackPanel Margin="12">
                                <TextBlock Text="Services" FontSize="11" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card1Value" Text="Loading…" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card1Sub" Text="SQL, WSUS, IIS" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card2Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Green}"/>
                            <StackPanel Margin="12">
                                <TextBlock Text="Database" FontSize="11" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card2Value" Text="Loading…" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card2Sub" Text="SUSDB" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card3Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Orange}"/>
                            <StackPanel Margin="12">
                                <TextBlock Text="Disk" FontSize="11" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card3Value" Text="Loading…" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card3Sub" Text="Free space" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card4Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Blue}"/>
                            <StackPanel Margin="12">
                                <TextBlock Text="Task" FontSize="11" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card4Value" Text="Loading…" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card4Sub" Text="Scheduled" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </UniformGrid>

                <!-- Health Score Band -->
                <Border Grid.Row="1" Background="{StaticResource BgCard}" CornerRadius="4" Margin="0,0,0,12" Padding="16,12">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel>
                            <TextBlock Text="Health Score" FontSize="12" Foreground="{StaticResource Text2}"/>
                            <TextBlock x:Name="HealthScoreValue" AutomationProperties.AutomationId="HealthScoreValue" Text=" -" FontSize="24" FontWeight="Bold" Foreground="{StaticResource Text1}"/>
                        </StackPanel>
                        <ProgressBar x:Name="HealthScoreBar" Grid.Column="1" Height="8" Minimum="0" Maximum="100" Value="0" Background="{StaticResource BgDark}" Foreground="{StaticResource Blue}" Margin="16,0" VerticalAlignment="Center"/>
                        <StackPanel Grid.Column="2" VerticalAlignment="Center">
                            <TextBlock x:Name="HealthScoreGrade" AutomationProperties.AutomationId="HealthScoreGrade" Text="" FontSize="12" FontWeight="Bold" Foreground="{StaticResource Green}" HorizontalAlignment="Right"/>
                            <TextBlock x:Name="LastSyncText" Text="Last sync:  -" FontSize="10" Foreground="{StaticResource Text2}" HorizontalAlignment="Right" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Grid>
                </Border>

                <!-- Quick Actions -->
                <StackPanel Grid.Row="2" Margin="0,0,0,16">
                    <TextBlock Text="Quick Actions" FontSize="12" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                    <WrapPanel>
                        <Button x:Name="QBtnDiagnostics" Content="Deep Diagnostics" Style="{StaticResource Btn}" Margin="0,0,12,0"/>
                        <Button x:Name="QBtnCleanup" Content="Deep Cleanup" Style="{StaticResource BtnSec}" Margin="0,0,12,0"/>
                        <Button x:Name="QBtnMaint" Content="Online Sync" Style="{StaticResource BtnSec}" Margin="0,0,12,0"/>
                        <Button x:Name="QBtnStart" Content="Start Services" Style="{StaticResource BtnGreen}"/>
                    </WrapPanel>
                </StackPanel>

                <!-- Config -->
                <Border Grid.Row="3" Background="{StaticResource BgCard}" CornerRadius="4" Padding="12" VerticalAlignment="Top">
                    <StackPanel>
                        <TextBlock Text="Configuration" FontSize="12" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="90"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Content:" Foreground="{StaticResource Text2}" FontSize="12"/>
                            <TextBlock x:Name="CfgContentPath" Grid.Column="1" Text="C:\WSUS" Foreground="{StaticResource Text1}" FontSize="12"/>
                            <TextBlock Grid.Row="1" Text="SQL:" Foreground="{StaticResource Text2}" FontSize="12" Margin="0,4,0,0"/>
                            <TextBlock x:Name="CfgSqlInstance" Grid.Row="1" Grid.Column="1" Text=".\SQLEXPRESS" Foreground="{StaticResource Text1}" FontSize="12" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="2" Text="Export:" Foreground="{StaticResource Text2}" FontSize="12" Margin="0,4,0,0"/>
                            <TextBlock x:Name="CfgExportRoot" Grid.Row="2" Grid.Column="1" Text="C:\" Foreground="{StaticResource Text1}" FontSize="12" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="3" Text="Logs:" Foreground="{StaticResource Text2}" FontSize="12" Margin="0,4,0,0"/>
                            <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" Margin="0,4,0,0">
                                <TextBlock x:Name="CfgLogPath" Foreground="{StaticResource Text1}" FontSize="12"/>
                                <Button x:Name="BtnOpenLog" Content="Open" FontSize="10" Padding="8,4" Margin="8,0,0,0" Background="#30363D" Foreground="{StaticResource Text2}" BorderThickness="0" Cursor="Hand"/>
                            </StackPanel>
                        </Grid>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Install Panel -->
            <Grid x:Name="InstallPanel" AutomationProperties.AutomationId="InstallPanel" Grid.Row="1" Visibility="Collapsed">
                <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16">
                    <StackPanel>
                        <TextBlock Text="Install WSUS + SQL Express" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                        <TextBlock Text="Select the folder containing SQL Server installers. Default is C:\WSUS\SQLDB." FontSize="12" Foreground="{StaticResource Text2}" TextWrapping="Wrap" Margin="0,0,0,12"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="InstallPathBox" TabIndex="1" Background="{StaticResource BgDark}" Foreground="{StaticResource Text1}" BorderThickness="1" BorderBrush="{StaticResource Border}" Padding="8,4"/>
                            <Button x:Name="BtnBrowseInstallPath" TabIndex="2" Grid.Column="1" Content="Browse" Style="{StaticResource BtnSec}" Padding="8,4" Margin="8,0,0,0"/>
                        </Grid>
                        <TextBlock Text="SQL Admin Password (SA):" FontSize="12" Foreground="{StaticResource Text2}" Margin="0,12,0,4"/>
                        <PasswordBox x:Name="InstallSaPassword" TabIndex="3" Background="{StaticResource BgDark}" Foreground="{StaticResource Text1}" BorderThickness="1" BorderBrush="{StaticResource Border}" Padding="8,4"/>
                        <TextBlock Text="Confirm SA Password:" FontSize="12" Foreground="{StaticResource Text2}" Margin="0,12,0,4"/>
                        <PasswordBox x:Name="InstallSaPasswordConfirm" TabIndex="4" Background="{StaticResource BgDark}" Foreground="{StaticResource Text1}" BorderThickness="1" BorderBrush="{StaticResource Border}" Padding="8,4"/>
                        <ProgressBar x:Name="PasswordStrength" Height="8" Margin="0,4,0,0" Visibility="Collapsed" Maximum="100"/>
                        <TextBlock x:Name="PasswordError" Foreground="{StaticResource Red}" FontSize="12" Margin="0,4,0,0" Visibility="Collapsed"/>
                        <TextBlock Text="Password must be 15+ chars with a number and special character." FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                        <ProgressBar x:Name="InstallProgress" Height="8" Margin="0,8,0,0" Visibility="Collapsed" Foreground="{StaticResource Blue}"/>
                        <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
                            <Button x:Name="BtnRunInstall" TabIndex="5" Content="Install WSUS" Style="{StaticResource BtnGreen}" Margin="0,0,8,0"/>
                            <TextBlock Text="Requires admin rights" FontSize="10" Foreground="{StaticResource Text3}" VerticalAlignment="Center"/>
                        </StackPanel>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Operation Panel -->
            <Grid x:Name="OperationPanel" AutomationProperties.AutomationId="OperationPanel" Grid.Row="1" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Border Background="{StaticResource BgCard}" CornerRadius="4">
                    <ScrollViewer x:Name="ConsoleScroller" VerticalScrollBarVisibility="Auto" Margin="12">
                        <TextBlock x:Name="ConsoleOutput" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource Text2}" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </Border>
<StackPanel Grid.Row="1" Margin="0,4,0,0">
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                        <Button x:Name="BtnBack" Content="Back" Style="{StaticResource BtnSec}"/>
                    </StackPanel>
                </StackPanel>
            </Grid>

            <!-- About Panel -->
            <ScrollViewer x:Name="AboutPanel" AutomationProperties.AutomationId="AboutPanel" Grid.Row="1" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                <StackPanel>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16" Margin="0,0,0,12">
                        <StackPanel Orientation="Horizontal">
                            <Image x:Name="AboutLogo" Width="56" Height="56" Margin="0,0,16,0" VerticalAlignment="Center"/>
                            <StackPanel VerticalAlignment="Center">
                                <TextBlock Text="WSUS Manager" FontSize="20" FontWeight="Bold" Foreground="{StaticResource Text1}"/>
                                 <TextBlock x:Name="AboutVersion" Text="Version ..." FontSize="12" Foreground="{StaticResource Text2}" Margin="0,4,0,0"/>
                                <TextBlock Text="Windows Server Update Services Management Tool" FontSize="12" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16" Margin="0,0,0,12">
                        <StackPanel>
                            <TextBlock Text="Author" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                            <TextBlock Text="Tony Tran" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource Blue}"/>
                            <TextBlock Text="ISSO, Classified Computing, GA-ASI" FontSize="12" Foreground="{StaticResource Text2}" Margin="0,4,0,0"/>
                            <TextBlock Text="tony.tran@ga-asi.com" FontSize="12" Foreground="{StaticResource Blue}" Margin="0,8,0,0"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16" Margin="0,0,0,12">
                        <StackPanel>
                            <TextBlock Text="Features" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                            <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="{StaticResource Text2}" LineHeight="20" Text="• Automated WSUS + SQL Express installation (auto-migrates WID to SQL)&#x0a;• Smart update policy: auto-decline superseded, &gt;6mo old, Preview/Beta, ARM64, 23H2 and lower, Edge non-stable, Office 365/2019/LTSC 2021 (keeps 2024), WSL&#x0a;• Auto-approve x64 Critical, Security, Definition, Updates, Rollups (.NET included; 25H2 kept for manual review)&#x0a;• Default products: Win 11, Server 2019, .NET Framework, Edge, Defender, Office 2016, SQL Server 2022, Security Essentials, Visual Studio 2022, Exchange 2019"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16">
                        <StackPanel>
                            <TextBlock Text="Requirements" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                            <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="{StaticResource Text2}" LineHeight="20" Text="• Windows Server 2019+&#x0a;• PowerShell 5.1+&#x0a;• SQL Server Express 2022&#x0a;• 150 GB+ disk space (recommended)"/>
                            <TextBlock Text="© 2026 GA-ASI. Internal use only." FontSize="10" Foreground="{StaticResource Text3}" Margin="0,12,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <!-- Help Panel -->
            <Grid x:Name="HelpPanel" AutomationProperties.AutomationId="HelpPanel" Grid.Row="1" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="12" Margin="0,0,0,12">
                    <WrapPanel>
                        <Button x:Name="HelpBtnOverview" Content="Overview" Style="{StaticResource BtnSec}" Padding="8,4" Margin="0,0,8,0"/>
                        <Button x:Name="HelpBtnDashboard" Content="Dashboard" Style="{StaticResource BtnSec}" Padding="8,4" Margin="0,0,8,0"/>
                        <Button x:Name="HelpBtnOperations" Content="Operations" Style="{StaticResource BtnSec}" Padding="8,4" Margin="0,0,8,0"/>
                        <Button x:Name="HelpBtnAirGap" Content="Air-Gap" Style="{StaticResource BtnSec}" Padding="8,4" Margin="0,0,8,0"/>
                        <Button x:Name="HelpBtnTroubleshooting" Content="Troubleshooting" Style="{StaticResource BtnSec}" Padding="8,4"/>
                    </WrapPanel>
                </Border>
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="20">
                        <StackPanel>
                            <TextBlock x:Name="HelpTitle" Text="Help" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,0,0,12"/>
                            <TextBlock x:Name="HelpText" TextWrapping="Wrap" FontSize="12" Foreground="{StaticResource Text2}" LineHeight="20"/>
                        </StackPanel>
                    </Border>
                </ScrollViewer>
            </Grid>

            <!-- History Panel -->
            <Grid x:Name="HistoryPanel" AutomationProperties.AutomationId="HistoryPanel" Grid.Row="1" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock Text="Operation History" FontSize="20" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,0,0,12"/>
                <Border Grid.Row="1" Background="{StaticResource BgCard}" CornerRadius="4" Padding="16">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="HistoryFilter" Background="{StaticResource BgDark}" Foreground="{StaticResource Text1}" BorderThickness="1" BorderBrush="{StaticResource Border}" Padding="8,4" FontSize="12" Margin="0,0,8,0" ToolTip="Filter by operation type, result, or keyword"/>
                            <Button x:Name="BtnRefreshHistory" Grid.Column="1" Content="↻ Refresh" Style="{StaticResource BtnSec}" Padding="8,4" Margin="0,0,8,0"/>
                            <Button x:Name="BtnClearHistory" Grid.Column="2" Content="✕ Clear History" Style="{StaticResource BtnSec}" Padding="8,4"/>
                        </Grid>
                        <ListBox x:Name="HistoryList" Grid.Row="1" AlternationCount="2" Background="{StaticResource BgDark}" BorderThickness="0" Foreground="{StaticResource Text1}" FontFamily="Consolas" FontSize="12" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                            <ListBox.ItemContainerStyle>
                                <Style TargetType="ListBoxItem">
                                    <Setter Property="Padding" Value="8,4"/>
                                    <Setter Property="BorderThickness" Value="0"/>
                                    <Setter Property="Background" Value="Transparent"/>
                                    <Style.Triggers>
                                        <Trigger Property="ItemsControl.AlternationIndex" Value="1">
                                            <Setter Property="Background" Value="#161B22"/>
                                        </Trigger>
                                    </Style.Triggers>
                                </Style>
                            </ListBox.ItemContainerStyle>
                        </ListBox>
                    </Grid>
                </Border>
            </Grid>

            <!-- Log Panel -->
            <Border x:Name="LogPanel" AutomationProperties.AutomationId="LogPanel" Grid.Row="2" Background="{StaticResource BgSidebar}" CornerRadius="4" Margin="0,12,0,0" Height="250">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Border Background="{StaticResource BgCard}" Padding="12,8" CornerRadius="4,4,0,0">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="Output Log" FontSize="12" FontWeight="SemiBold" Foreground="{StaticResource Text1}" VerticalAlignment="Center"/>
                                <TextBlock x:Name="StatusLabel" Text=" - Ready" FontSize="10" Foreground="{StaticResource Text2}" VerticalAlignment="Center" Margin="8,0,0,0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button x:Name="BtnCancelOp" Content="Cancel" Background="{StaticResource Red}" Foreground="{StaticResource Text1}" BorderThickness="0" Padding="8,4" FontSize="10" Margin="0,0,8,0" Visibility="Collapsed"/>
                                <Button x:Name="BtnLiveTerminal" Content="Live Terminal: Off" Style="{StaticResource BtnSec}" Padding="8,4" FontSize="10" Margin="0,0,8,0" ToolTip="Toggle between embedded log and live PowerShell console"/>
                                <Button x:Name="BtnToggleLog" Content="Hide" Style="{StaticResource BtnSec}" Padding="8,4" FontSize="10" Margin="0,0,8,0"/>
                                <Button x:Name="BtnClearLog" Content="Clear" Style="{StaticResource BtnSec}" Padding="8,4" FontSize="10" Margin="0,0,8,0"/>
                                <Button x:Name="BtnSaveLog" Content="Save" Style="{StaticResource BtnSec}" Padding="8,4" FontSize="10"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <TextBox x:Name="LogOutput" Grid.Row="1" IsReadOnly="True" TextWrapping="NoWrap"
                             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                             FontFamily="Consolas" FontSize="12" Background="{StaticResource BgDark}"
                             Foreground="{StaticResource Text2}" BorderThickness="0" Padding="12,8"/>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@
#endregion

#region Create Window
$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:window = [Windows.Markup.XamlReader]::Load($reader)

$script:controls = @{}
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    if ($_.Name) { $script:controls[$_.Name] = $script:window.FindName($_.Name) }
}
#endregion

# Palette brush variables for programmatic UI
$script:BrushBgDark = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
$script:BrushBgSidebar = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#161B22")
$script:BrushBgCard = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
$script:BrushBorder = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
$script:BrushBlue = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
$script:BrushGreen = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#3FB950")
$script:BrushOrange = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#D29922")
$script:BrushRed = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F85149")
$script:BrushText1 = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
$script:BrushText2 = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
$script:BrushText3 = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#6E7681")

#region Keyboard Shortcuts
$script:window.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::D -and $e.KeyboardDevice.Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        # Ctrl+D = Diagnostics
        if ($controls.BtnDiagnostics -and $controls.BtnDiagnostics.IsEnabled) { $controls.BtnDiagnostics.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
    }
    elseif ($e.Key -eq [System.Windows.Input.Key]::S -and $e.KeyboardDevice.Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        # Ctrl+S = Online Sync
        if ($controls.BtnMaintenance -and $controls.BtnMaintenance.IsEnabled) { $controls.BtnMaintenance.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
    }
    elseif ($e.Key -eq [System.Windows.Input.Key]::H -and $e.KeyboardDevice.Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        # Ctrl+H = History
        if ($controls.BtnHistory) { $controls.BtnHistory.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)) }
    }
    elseif (($e.Key -eq [System.Windows.Input.Key]::R -and $e.KeyboardDevice.Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) -or $e.Key -eq [System.Windows.Input.Key]::F5) {
        # Ctrl+R or F5 = Refresh dashboard
        Invoke-DashboardRefreshSafe -Source "Keyboard Shortcut"
    }
})
if ($controls.BtnDiagnostics) { $controls.BtnDiagnostics.ToolTip = "Run deep WSUS diagnostics and safe repair checks (Ctrl+D)" }
if ($controls.BtnMaintenance) { $controls.BtnMaintenance.ToolTip = "Online Sync (Ctrl+S)" }
#endregion

#region Helper Functions
$script:LogExpanded = $true
$script:HasTrendingModule = [bool](Get-Command Add-WsusTrendSnapshot -ErrorAction SilentlyContinue)
$script:HasHealthModule = [bool](Get-Command Get-WsusHealthScore -ErrorAction SilentlyContinue)
$script:HasNotificationModule = [bool](Get-Command Show-WsusNotification -ErrorAction SilentlyContinue)
$script:CachedSqlCmdPath = $null
$script:SettingsCorrupt = $false

function Expand-LogPanel {
    if (-not $script:LogExpanded) {
        $controls.LogPanel.Height = 250
        $controls.BtnToggleLog.Content = "Hide"
        $script:LogExpanded = $true
    }
}

function Save-LogToFile {
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "Text Files (*.txt)|*.txt"
    $dialog.FileName = "WsusManager-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    if ($dialog.ShowDialog() -eq $true) {
        $controls.LogOutput.Text | Out-File $dialog.FileName -Encoding UTF8
        Write-LogOutput "Log saved to $($dialog.FileName)" -Level Success
    }
}

function Show-SplashScreen {
<#
.SYNOPSIS
    Displays a lightweight splash screen during application startup.
.DESCRIPTION
    Shows a borderless window with logo, version, and progress bar.
    Progress updates as each startup stage completes.
    Auto-dismisses when the main window is ready.
.OUTPUTS
    Returns a hashtable with Window, ProgressBar, StatusText, and Close scriptblock.
#>
    try {
        $splash = New-Object System.Windows.Window
        $splash.Title = "WSUS Manager"
        $splash.Width = 400
        $splash.Height = 220
        $splash.WindowStartupLocation = "CenterScreen"
        $splash.WindowStyle = "None"
        $splash.Background = $script:BrushBgDark
        $splash.ResizeMode = "NoResize"
        $splash.Topmost = $true
        $splash.AllowsTransparency = $false

        $border = New-Object System.Windows.Controls.Border
        $border.Background = $script:BrushBgSidebar
        $border.BorderBrush = $script:BrushBorder
        $border.BorderThickness = "1"

        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = "32"

        $r0 = New-Object System.Windows.Controls.RowDefinition; $r0.Height = "Auto"
        $r1 = New-Object System.Windows.Controls.RowDefinition; $r1.Height = "Auto"
        $r2 = New-Object System.Windows.Controls.RowDefinition; $r2.Height = "Auto"
        $r3 = New-Object System.Windows.Controls.RowDefinition; $r3.Height = "Auto"
        $grid.RowDefinitions.Add($r0)
        $grid.RowDefinitions.Add($r1)
        $grid.RowDefinitions.Add($r2)
        $grid.RowDefinitions.Add($r3)

        $titleText = New-Object System.Windows.Controls.TextBlock
        $titleText.Text = "WSUS Manager"
        $titleText.FontSize = 20
        $titleText.FontWeight = "Bold"
        $titleText.Foreground = $script:BrushText1
        $titleText.HorizontalAlignment = "Center"
        $titleText.Margin = "0,0,0,4"
        [System.Windows.Controls.Grid]::SetRow($titleText, 0)
        $null = $grid.Children.Add($titleText)

        $versionText = New-Object System.Windows.Controls.TextBlock
        $versionText.Text = "v$script:AppVersion"
        $versionText.FontSize = 10
        $versionText.Foreground = $script:BrushText2
        $versionText.HorizontalAlignment = "Center"
        $versionText.Margin = "0,0,0,20"
        [System.Windows.Controls.Grid]::SetRow($versionText, 1)
        $null = $grid.Children.Add($versionText)

        $progressBar = New-Object System.Windows.Controls.ProgressBar
        $progressBar.Minimum = 0
        $progressBar.Maximum = 100
        $progressBar.Value = 0
        $progressBar.Height = 8
        $progressBar.Background = $script:BrushBgCard
        $progressBar.Foreground = $script:BrushBlue
        $progressBar.BorderThickness = "0"
        $progressBar.Margin = "0,0,0,8"
        [System.Windows.Controls.Grid]::SetRow($progressBar, 2)
        $null = $grid.Children.Add($progressBar)

        $statusText = New-Object System.Windows.Controls.TextBlock
        $statusText.Text = "Initializing..."
        $statusText.FontSize = 10
        $statusText.Foreground = $script:BrushText2
        $statusText.HorizontalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetRow($statusText, 3)
        $null = $grid.Children.Add($statusText)

        $border.Child = $grid
        $splash.Content = $border

        $splash.Show()
        $splash.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)

        return @{
            Window     = $splash
            ProgressBar = $progressBar
            StatusText  = $statusText
            Close       = { param($s) try { $s.Window.Close() } catch { Write-Verbose $_.Exception.Message } }
        }
    } catch {
        Write-Log "Splash screen failed: $_"
        return $null
    }
}

function Update-SplashProgress {
<#
.SYNOPSIS Updates splash screen progress bar and status message.
#>
    param(
        [hashtable]$Splash,
        [int]$Progress,
        [string]$Status
    )
    if ($null -eq $Splash) { return }
    try {
        $Splash.ProgressBar.Value = $Progress
        $Splash.StatusText.Text = $Status
        $Splash.Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    } catch { Write-Verbose $_.Exception.Message }
}

function Write-LogOutput {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')][string]$Level = 'Info'
    )
    Write-WsusGuiLogOutput -Controls $controls -Message $Message -Level $Level
}

function Set-Status {
    param([string]$Text)
    Set-WsusGuiStatusText -Controls $controls -Text $Text -UseDashPrefix
}

function Show-WsusPopup {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = "WSUS Manager",
        [System.Windows.MessageBoxButton]$Button = [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]$Icon = [System.Windows.MessageBoxImage]::Information,
        [int]$SuppressDuplicateSeconds = 0
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return [System.Windows.MessageBoxResult]::None
    }

    if (Test-WsusGuiPopupSuppressed -Message $Message -Title $Title -Button $Button -Icon $Icon -SuppressDuplicateSeconds $SuppressDuplicateSeconds -PopupHistory $script:PopupHistory) {
        Write-Log "Popup suppressed (duplicate within $SuppressDuplicateSeconds s): $Title"
        return [System.Windows.MessageBoxResult]::None
    }

    if ($script:E2EStartupProbe) {
        Add-WsusGuiPopupEvent -EventList $script:E2EPopupEvents -Message $Message -Title $Title -Button $Button -Icon $Icon
        $probeResult = Get-WsusGuiProbePopupResult -Button $Button
        switch ($probeResult) {
            'No'     { return [System.Windows.MessageBoxResult]::No }
            'Cancel' { return [System.Windows.MessageBoxResult]::Cancel }
            default  { return [System.Windows.MessageBoxResult]::OK }
        }
    }

    try {
        if ($script:window -and $script:window.IsLoaded -and $script:window.IsVisible) {
            return [System.Windows.MessageBox]::Show($script:window, $Message, $Title, $Button, $Icon)
        }
        return [System.Windows.MessageBox]::Show($Message, $Title, $Button, $Icon)
    } catch {
        try {
            $wfButtons = switch ($Button) {
                ([System.Windows.MessageBoxButton]::OKCancel) { [System.Windows.Forms.MessageBoxButtons]::OKCancel }
                ([System.Windows.MessageBoxButton]::YesNo) { [System.Windows.Forms.MessageBoxButtons]::YesNo }
                ([System.Windows.MessageBoxButton]::YesNoCancel) { [System.Windows.Forms.MessageBoxButtons]::YesNoCancel }
                default { [System.Windows.Forms.MessageBoxButtons]::OK }
            }

            $wfIcon = switch ($Icon) {
                ([System.Windows.MessageBoxImage]::Error) { [System.Windows.Forms.MessageBoxIcon]::Error }
                ([System.Windows.MessageBoxImage]::Warning) { [System.Windows.Forms.MessageBoxIcon]::Warning }
                ([System.Windows.MessageBoxImage]::Question) { [System.Windows.Forms.MessageBoxIcon]::Question }
                ([System.Windows.MessageBoxImage]::Information) { [System.Windows.Forms.MessageBoxIcon]::Information }
                default { [System.Windows.Forms.MessageBoxIcon]::None }
            }

            $wfResult = [System.Windows.Forms.MessageBox]::Show($Message, $Title, $wfButtons, $wfIcon)
            switch ($wfResult) {
                ([System.Windows.Forms.DialogResult]::OK)     { return [System.Windows.MessageBoxResult]::OK }
                ([System.Windows.Forms.DialogResult]::Cancel) { return [System.Windows.MessageBoxResult]::Cancel }
                ([System.Windows.Forms.DialogResult]::Yes)    { return [System.Windows.MessageBoxResult]::Yes }
                ([System.Windows.Forms.DialogResult]::No)     { return [System.Windows.MessageBoxResult]::No }
                default                                       { return [System.Windows.MessageBoxResult]::None }
            }
        } catch {
            Write-Log "Popup fallback failed: $($_.Exception.Message)" "Error"
            return [System.Windows.MessageBoxResult]::None
        }
    }
}

# Dashboard data functions - delegate to WsusAutoDetection module with inline fallbacks
function Get-ServiceStatus {
    if (Get-Command Get-WsusDashboardServiceStatus -ErrorAction SilentlyContinue) { return Get-WsusDashboardServiceStatus }
    return @{Running=0; Names=@()}
}
function Get-DiskFreeGB {
    if (Get-Command Get-WsusDashboardDiskFreeGB -ErrorAction SilentlyContinue) { return Get-WsusDashboardDiskFreeGB }
    try { $d = Get-PSDrive -Name "C" -ErrorAction SilentlyContinue; if ($d.Free) { return [math]::Round($d.Free/1GB,1) } } catch { Write-Verbose $_.Exception.Message }
    return 0
}
function Get-DatabaseSizeGB {
    if (Get-Command Get-WsusDashboardDatabaseSizeGB -ErrorAction SilentlyContinue) { return Get-WsusDashboardDatabaseSizeGB -SqlInstance $script:SqlInstance }
    return -1
}
function Get-TaskStatus {
    if (Get-Command Get-WsusDashboardTaskStatus -ErrorAction SilentlyContinue) { return Get-WsusDashboardTaskStatus }
    return "Not Set"
}
function Test-InternetConnection {
    if (Get-Command Test-WsusDashboardInternetConnection -ErrorAction SilentlyContinue) { return Test-WsusDashboardInternetConnection }
    $ping = $null
    try { $ping = New-Object System.Net.NetworkInformation.Ping; $reply = $ping.Send("8.8.8.8", 500); return ($null -ne $reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) }
    catch { return $false }
    finally { if ($null -ne $ping) { $ping.Dispose() } }
}

function Update-ServerMode {
    # Use manual override if set, otherwise auto-detect
    if ($script:ServerModeOverride) {
        $isOnline = ($script:ServerModeOverride -eq "Online")
    } else {
        $isOnline = Test-InternetConnection
    }
    $script:ServerMode = if ($isOnline) { "Online" } else { "Air-Gap" }

    if ($controls.InternetStatusDot -and $controls.InternetStatusText) {
        $controls.InternetStatusDot.Fill = if ($isOnline) { $window.FindResource("Green") } else { $window.FindResource("Red") }
        $label = if ($isOnline) { "Online" } else { "Offline" }
        if ($script:ServerModeOverride) { $label += " (Manual)" }
        $controls.InternetStatusText.Text = $label
        $controls.InternetStatusText.Foreground = if ($isOnline) { $window.FindResource("Green") } else { $window.FindResource("Red") }
    }

    if ($controls.BtnMaintenance) {
        $controls.BtnMaintenance.IsEnabled = $isOnline
        $controls.BtnMaintenance.Opacity = if ($isOnline) { 1.0 } else { 0.5 }
    }
    if ($controls.BtnSchedule) {
        $controls.BtnSchedule.IsEnabled = $isOnline
        $controls.BtnSchedule.Opacity = if ($isOnline) { 1.0 } else { 0.5 }
    }
    if ($controls.QBtnMaint) {
        $controls.QBtnMaint.IsEnabled = $isOnline
        $controls.QBtnMaint.Opacity = if ($isOnline) { 1.0 } else { 0.5 }
    }
}

function Test-PasswordStrength($candidate) {
    $strength = 0
    if ($candidate.Length -ge 15) { $strength += 40 }
    if ($candidate -match '\d') { $strength += 30 }
    if ($candidate -match '[^a-zA-Z0-9]') { $strength += 30 }
    return $strength
}


function Update-Dashboard {
    Update-ServerMode

    # Check if WSUS is installed first
    $wsusInstalled = Test-WsusInstalled
    $script:WsusInstalled = $wsusInstalled

    # Skip heavy queries if WSUS not installed - just update button state
    if (-not $wsusInstalled) {
        Update-WsusButtonState
        return
    }

    $dashboardData = $null
    if (Get-Command Get-WsusDashboardSnapshot -ErrorAction SilentlyContinue) {
        $snapshot = Get-WsusDashboardSnapshot -SqlInstance $script:SqlInstance -ModulePath $script:ModulesDir
        if ($snapshot -and $snapshot.Data) { $dashboardData = $snapshot.Data }
    }

    $dashboardView = if (Get-Command New-WsusDashboardViewModel -ErrorAction SilentlyContinue) {
        New-WsusDashboardViewModel -WsusInstalled:$wsusInstalled -ServerMode $script:ServerMode -ServerModeOverridden:([bool]$script:ServerModeOverride) `
            -DashboardData $dashboardData -ContentPath $script:ContentPath -SqlInstance $script:SqlInstance -ExportRoot $script:ExportRoot -LogPath $script:LogDir
    } else {
        $null
    }

    # Card 1: Services
    if ($controls.Card1Value -and $controls.Card1Sub -and $controls.Card1Bar) {
        $servicesCard = if ($dashboardView) { $dashboardView.Cards.Services } else { $null }
        if ($servicesCard) {
            $controls.Card1Value.Text = $servicesCard.Value
            $controls.Card1Sub.Text = $servicesCard.Sub
            $controls.Card1Bar.Background = switch ($servicesCard.Status) {
                'Pass' { '#3FB950' }
                'Warn' { '#D29922' }
                'Skip' { '#30363D' }
                default { '#F85149' }
            }
        }
    }

    # Card 2: Database
    if ($controls.Card2Value -and $controls.Card2Sub -and $controls.Card2Bar) {
        $databaseCard = if ($dashboardView) { $dashboardView.Cards.Database } else { $null }
        if ($databaseCard) {
            $controls.Card2Value.Text = $databaseCard.Value
            $controls.Card2Sub.Text = $databaseCard.Sub
            $controls.Card2Bar.Background = switch ($databaseCard.Status) {
                'Pass' { '#3FB950' }
                'Warn' { '#D29922' }
                'Skip' { '#30363D' }
                default { '#F85149' }
            }
        }

        $db = if ($dashboardData) { $dashboardData.DatabaseSizeGB } else { Get-DatabaseSizeGB }
        if ($script:HasTrendingModule -and $db -ge 0) {
            Add-WsusTrendSnapshot -DatabaseSizeGB $db
            $trend = Get-WsusTrendSummary
            if ($trend -and $trend.Status -eq "OK") {
                $sign = if ($trend.GrowthPerMonth -ge 0) { "+" } else { "" }
                $trendTxt = "$db GB  $sign$([math]::Round($trend.GrowthPerMonth,1))/mo"
                if ($null -ne $controls.Card2Sub) { $controls.Card2Sub.Text = $trendTxt }
                if ($trend.AlertLevel -eq "Critical" -and $null -ne $controls.Card2Sub) {
                    $controls.Card2Sub.Text = "⚠ $($trend.DaysUntilFull) days until full"
                    $controls.Card2Sub.Foreground = $window.FindResource("Red")
                } elseif ($trend.AlertLevel -eq "Warning") {
                    $controls.Card2Sub.Foreground = $window.FindResource("Orange")
                }
            } elseif ($trend -and $trend.Status -ne "OK" -and $null -ne $controls.Card2Sub) {
                $controls.Card2Sub.Text = "Collecting trend data..."
            }
        }
    }

    # Card 3: Disk
    if ($controls.Card3Value -and $controls.Card3Sub -and $controls.Card3Bar) {
        $diskCard = if ($dashboardView) { $dashboardView.Cards.Disk } else { $null }
        if ($diskCard) {
            $controls.Card3Value.Text = $diskCard.Value
            $controls.Card3Sub.Text = $diskCard.Sub
            $controls.Card3Bar.Background = switch ($diskCard.Status) {
                'Pass' { '#3FB950' }
                'Warn' { '#D29922' }
                default { '#F85149' }
            }
        }
    }

    # Card 4: Task
    if ($controls.Card4Value -and $controls.Card4Bar) {
        $taskCard = if ($dashboardView) { $dashboardView.Cards.Task } else { $null }
        if ($taskCard) {
            $controls.Card4Value.Text = $taskCard.Value
            $controls.Card4Bar.Background = switch ($taskCard.Status) {
                'Pass' { '#3FB950' }
                'Skip' { '#30363D' }
                default { '#D29922' }
            }
        }
    }

    # Configuration display
    if ($dashboardView -and $dashboardView.Configuration) {
        if ($controls.CfgContentPath) { $controls.CfgContentPath.Text = $dashboardView.Configuration.ContentPath }
        if ($controls.CfgSqlInstance) { $controls.CfgSqlInstance.Text = $dashboardView.Configuration.SqlInstance }
        if ($controls.CfgExportRoot) { $controls.CfgExportRoot.Text = $dashboardView.Configuration.ExportRoot }
        if ($controls.CfgLogPath) { $controls.CfgLogPath.Text = $dashboardView.Configuration.LogPath }
    }
    if ($controls.StatusLabel) { $controls.StatusLabel.Text = "Updated $(Get-Date -Format 'HH:mm:ss')" }

    # Update Health Score
    if ($controls.HealthScoreValue -and $script:HasHealthModule) {
        try {
            $health = Get-WsusHealthScore -SqlInstance $script:SqlInstance -ContentPath $script:ContentPath
            if ($health.Score -ge 0) {
                $controls.HealthScoreValue.Text = "$($health.Score)"
                $controls.HealthScoreBar.Value = $health.Score
                $scoreBrush = switch($health.Grade) {
                    "Green"   { $script:BrushGreen }
                    "Yellow"  { $script:BrushOrange }
                    default   { $script:BrushRed }
                }
                $controls.HealthScoreValue.Foreground = $scoreBrush
                $controls.HealthScoreGrade.Text = $health.Grade
                $controls.HealthScoreGrade.Foreground = $scoreBrush
                # Update tray tooltip with health grade
                if ($null -ne $script:TrayIcon) {
                    $script:TrayIcon.Text = "WSUS Manager  - Health: $($health.Grade) ($($health.Score)/100)"
                }
            } else {
                $controls.HealthScoreValue.Text = "N/A"
                $controls.HealthScoreGrade.Text = "Unknown"
            }
        } catch { Write-Verbose $_.Exception.Message }
    }

    # Last Successful Sync (skip if WSUS service is not running to avoid blocking)
    if ($controls.LastSyncText -and $wsusInstalled) {
        try {
            $wsusRunning = (Get-Service -Name "WSUSService" -ErrorAction SilentlyContinue).Status -eq "Running"
            if (-not $wsusRunning) { throw "WSUS service not running" }
            $wsus = Get-WsusServer -ErrorAction Stop
            if ($wsus) {
                $sub = $wsus.GetSubscription()
                $lastSync = $sub.LastSuccessfulSynchronizationTime
                # Fallback: LastSuccessfulSynchronizationTime can return MinValue on air-gapped servers
                # even after a successful sync -- check GetLastSynchronizationInfo() instead
                if (-not $lastSync -or $lastSync -eq [DateTime]::MinValue) {
                    $syncInfo = $sub.GetLastSynchronizationInfo()
                    if ($syncInfo -and $syncInfo.Result -eq [Microsoft.UpdateServices.Administration.SynchronizationResult]::Succeeded) {
                        $lastSync = $syncInfo.StartTime
                    }
                }
                if ($lastSync -and $lastSync -ne [DateTime]::MinValue) {
                    $daysAgo = [int]([DateTime]::Now - $lastSync).TotalDays
                    $lastSyncStr = if ($daysAgo -eq 0) { "today" } elseif ($daysAgo -eq 1) { "yesterday" } else { "$daysAgo days ago" }
                    $controls.LastSyncText.Text = "Last sync: $lastSyncStr ($($lastSync.ToString('MMM d, yyyy HH:mm')))"
                    $controls.LastSyncText.Foreground = if ($daysAgo -le 7) { $script:BrushGreen } elseif ($daysAgo -le 30) { $script:BrushOrange } else { $script:BrushRed }
                } else {
                    $controls.LastSyncText.Text = "Last sync: Never"
                    $controls.LastSyncText.Foreground = $script:BrushRed
                }
            }
        } catch {
            $controls.LastSyncText.Text = "Last sync: unavailable"
        }
    }

    # Check WSUS installation and update button states
    Update-WsusButtonState
}

function Invoke-DashboardRefreshSafe {
    param([string]$Source = "Unknown")

    if ($script:RefreshInProgress -or $script:OperationRunning) { return }

    $script:RefreshInProgress = $true
    try {
        Update-Dashboard
    } catch {
        Write-Log "Dashboard refresh failed ($Source): $($_.Exception.Message)"
        if ($controls.LogOutput) {
            Write-LogOutput "Dashboard refresh failed ($Source): $($_.Exception.Message)" -Level Warning
        }
    } finally {
        $script:RefreshInProgress = $false
    }
}

function Update-HistoryView {
    if (-not $controls.HistoryList) { return }
    $controls.HistoryList.Items.Clear()

    # Get filter text for history search
    $filterText = ""
    if ($controls.HistoryFilter -and $controls.HistoryFilter.Text) {
        $filterText = $controls.HistoryFilter.Text.Trim().ToLower()
    }

    # Try WsusHistory module first
    if (Get-Command Get-WsusOperationHistory -ErrorAction SilentlyContinue) {
        $entries = Get-WsusOperationHistory -Count 50
        if ($entries -and $entries.Count -gt 0) {
            foreach ($entry in ($entries | Where-Object {
                if ([string]::IsNullOrEmpty($filterText)) { $true }
                else { ($_.OperationType -and $_.OperationType.ToLower().Contains($filterText)) -or ($_.Result -and $_.Result.ToLower().Contains($filterText)) -or ($_.Summary -and $_.Summary.ToLower().Contains($filterText)) }
            })) {
                $ts = try { ([DateTime]$entry.Timestamp).ToString("yyyy-MM-dd HH:mm") } catch { "Unknown" }
                $dur = if ($entry.DurationSeconds) { "$($entry.DurationSeconds)s" } else { " -" }
                $icon = if ($entry.Result -eq "Pass") { "[+]" } else { "[-]" }
                $line = "$ts  $icon  $($entry.OperationType.PadRight(15))  $($dur.PadLeft(8))"
                if ($entry.Summary) { $line += "  $($entry.Summary)" }
                $item = New-Object System.Windows.Controls.ListBoxItem
                $item.Content = $line
                $item.Foreground = if ($entry.Result -eq "Pass") {
                    $script:BrushGreen
                } else {
                    $script:BrushRed
                }
                $null = $controls.HistoryList.Items.Add($item)
            }
            return
        }
    }

    # Fallback: parse recent log files from the app log directory
    $logDir = $script:LogDir
    if (-not $logDir) { $logDir = "C:\WSUS\Logs" }
    $logFiles = @()
    if (Test-Path $logDir) {
        $logFiles = Get-ChildItem -Path $logDir -Filter "WsusOperations_*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 5
    }
    # Also try the currently active log file
    if ($logFiles.Count -eq 0 -and $script:LogPath -and (Test-Path $script:LogPath)) {
        $logFiles = @(Get-Item $script:LogPath -ErrorAction SilentlyContinue)
    }
    if ($logFiles.Count -gt 0) {
        $lines = @()
        foreach ($lf in $logFiles) {
            $raw = Get-Content -Path $lf.FullName -ErrorAction SilentlyContinue
            if ($raw) { $lines += $raw }
        }
        $lines = ($lines | Where-Object { $_ -match '^\[' }) | Select-Object -Last 50
        if ($lines.Count -gt 0) {
            foreach ($line in $lines) {
                $item = New-Object System.Windows.Controls.ListBoxItem
                $item.Content = $line
                $item.Foreground = if ($line -match "ERROR|FAIL|Failed") {
                    $script:BrushRed
                } elseif ($line -match "SUCCESS|PASS|\[\+\]|Starting v") {
                    $script:BrushGreen
                } else {
                    $script:BrushText2
                }
                $null = $controls.HistoryList.Items.Add($item)
            }
            return
        }
    }
    $item = New-Object System.Windows.Controls.ListBoxItem
    $item.Content = "No operation history yet. Run an operation to start tracking."
    $item.Foreground = $script:BrushText2
    $null = $controls.HistoryList.Items.Add($item)
}

function Set-ActiveNavButton {
    param([string]$Active)
    $navBtns = @("BtnDashboard","BtnInstall","BtnFixSqlLogin","BtnRestore","BtnCreateGpo","BtnTransfer","BtnMaintenance","BtnSchedule","BtnCleanup","BtnDiagnostics","BtnReset","BtnAbout","BtnHelp","BtnHistory")
    foreach ($b in $navBtns) {
        if ($controls[$b]) {
            $controls[$b].Background = if($b -eq $Active){"#21262D"}else{"Transparent"}
            $controls[$b].Foreground = if($b -eq $Active){"#E6EDF3"}else{"#8B949E"}
            $controls[$b].BorderBrush = if($b -eq $Active){"#58A6FF"}else{"Transparent"}
            $controls[$b].BorderThickness = if($b -eq $Active){"2,0,0,0"}else{"0"}
        }
    }
}

# Operation buttons that should be disabled during operations
$script:OperationButtons = @("BtnInstall","BtnFixSqlLogin","BtnRestore","BtnCreateGpo","BtnTransfer","BtnMaintenance","BtnSchedule","BtnCleanup","BtnDiagnostics","BtnReset","QBtnDiagnostics","QBtnCleanup","QBtnMaint","QBtnStart","BtnRunInstall","BtnBrowseInstallPath")
# Input fields that should be disabled during operations
$script:OperationInputs = @("InstallSaPassword","InstallSaPasswordConfirm","InstallPathBox")
# Buttons that require WSUS to be installed (all except Install WSUS)
$script:WsusRequiredButtons = @("BtnRestore","BtnCreateGpo","BtnTransfer","BtnMaintenance","BtnSchedule","BtnCleanup","BtnDiagnostics","BtnReset","QBtnDiagnostics","QBtnCleanup","QBtnMaint","QBtnStart")
# Track WSUS installation status
$script:WsusInstalled = $false

function Disable-OperationButtons {
    foreach ($b in $script:OperationButtons) {
        if ($controls[$b]) {
            $controls[$b].IsEnabled = $false
            $controls[$b].Opacity = 0.5
        }
    }
    # Also disable input fields during operations
    foreach ($i in $script:OperationInputs) {
        if ($controls[$i]) {
            $controls[$i].IsEnabled = $false
            $controls[$i].Opacity = 0.5
        }
    }
}

function Enable-OperationButtons {
    foreach ($b in $script:OperationButtons) {
        if ($controls[$b]) {
            $controls[$b].IsEnabled = $true
            $controls[$b].Opacity = 1.0
        }
    }
    # Also re-enable input fields
    foreach ($i in $script:OperationInputs) {
        if ($controls[$i]) {
            $controls[$i].IsEnabled = $true
            $controls[$i].Opacity = 1.0
        }
    }
    # Re-check WSUS installation to disable buttons if WSUS not installed
    Update-WsusButtonState
}

function Test-WsusInstalled {
    # Check if WSUS service exists (not just running, but installed)
    try {
        $svc = Get-Service -Name "WSUSService" -ErrorAction SilentlyContinue
        return ($null -ne $svc)
    } catch {
        return $false
    }
}

function Update-WsusButtonState {
    # Disable/enable buttons based on WSUS installation status
    $script:WsusInstalled = Test-WsusInstalled

    if (-not $script:WsusInstalled) {
        # WSUS not installed - disable all buttons except Install WSUS
        foreach ($b in $script:WsusRequiredButtons) {
            if ($controls[$b]) {
                $controls[$b].IsEnabled = $false
                $controls[$b].Opacity = 0.5
                $controls[$b].ToolTip = "WSUS is not installed. Use 'Install WSUS' first."
            }
        }
        Write-Log "WSUS not installed - operations disabled"
    } else {
        # WSUS installed - enable buttons (unless operation is running)
        if (-not $script:OperationRunning) {
            foreach ($b in $script:WsusRequiredButtons) {
                if ($controls[$b]) {
                    $controls[$b].IsEnabled = $true
                    $controls[$b].Opacity = 1.0
                    $controls[$b].ToolTip = $null
                }
            }
        }
    }
}

function Stop-CurrentOperation {
    # Properly cleans up all resources from a running operation
    # Unregisters events, stops timers, disposes process, resets state
    param([switch]$SuppressLog)

    if (Get-Command Stop-WsusOperation -ErrorAction SilentlyContinue) {
        try { Stop-WsusOperation -Process $script:CurrentProcess } catch { Write-Verbose $_.Exception.Message }
    }

    # 1. Stop all timers first (prevents race conditions)
    if ($null -ne $script:OpCheckTimer) {
        try {
            $script:OpCheckTimer.Stop()
            $script:OpCheckTimer = $null
        } catch {
            if (-not $SuppressLog) { Write-Log "Timer stop warning: $_" }
        }
    }

    if ($null -ne $script:KeystrokeTimer) {
        try {
            $script:KeystrokeTimer.Stop()
            $script:KeystrokeTimer = $null
        } catch {
            if (-not $SuppressLog) { Write-Log "KeystrokeTimer stop warning: $_" }
        }
    }

    if ($null -ne $script:StdinFlushTimer) {
        try {
            $script:StdinFlushTimer.Stop()
            $script:StdinFlushTimer = $null
        } catch {
            if (-not $SuppressLog) { Write-Log "StdinFlushTimer stop warning: $_" }
        }
    }

    # 2. Unregister all event subscriptions (CRITICAL for preventing duplicates)
    foreach ($job in @($script:OutputEventJob, $script:ErrorEventJob, $script:ExitEventJob)) {
        if ($null -ne $job) {
            try {
                Unregister-Event -SourceIdentifier $job.Name -ErrorAction SilentlyContinue
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            } catch {
                if (-not $SuppressLog) { Write-Log "Event cleanup warning: $_" }
            }
        }
    }
    $script:OutputEventJob = $null
    $script:ErrorEventJob = $null
    $script:ExitEventJob = $null

    # 3. Dispose the process object
    if ($null -ne $script:CurrentProcess) {
        try {
            if (-not $script:CurrentProcess.HasExited) {
                $script:CurrentProcess.Kill()
                $script:CurrentProcess.WaitForExit(1000)
            }
            $script:CurrentProcess.Dispose()
        } catch {
            if (-not $SuppressLog) { Write-Log "Process cleanup warning: $_" }
        }
        $script:CurrentProcess = $null
    }

    # 4. Clear deduplication cache
    $script:RecentLines = @{}

    # 5. Reset operation state
    $script:OperationRunning = $false
}

function Show-Panel {
    param([string]$Panel, [string]$Title, [string]$NavBtn)
    $controls.PageTitle.Text = $Title
    $controls.DashboardPanel.Visibility = if($Panel -eq "Dashboard"){"Visible"}else{"Collapsed"}
    $controls.InstallPanel.Visibility = if($Panel -eq "Install"){"Visible"}else{"Collapsed"}
    $controls.OperationPanel.Visibility = if($Panel -eq "Operation"){"Visible"}else{"Collapsed"}
    $controls.AboutPanel.Visibility = if($Panel -eq "About"){"Visible"}else{"Collapsed"}
    $controls.HelpPanel.Visibility = if($Panel -eq "Help"){"Visible"}else{"Collapsed"}
    if ($controls.HistoryPanel) { $controls.HistoryPanel.Visibility = if($Panel -eq "History"){"Visible"}else{"Collapsed"} }
    Set-ActiveNavButton $NavBtn
    if ($Panel -eq "Dashboard") { Invoke-DashboardRefreshSafe -Source "Panel Navigation" }

    # Fade-in animation for panel transitions
    $targetPanel = switch ($Panel) {
        "Dashboard" { $controls.DashboardPanel }
        "Install"   { $controls.InstallPanel }
        "Operation" { $controls.OperationPanel }
        "About"     { $controls.AboutPanel }
        "Help"      { $controls.HelpPanel }
        "History"   { if ($controls.HistoryPanel) { $controls.HistoryPanel } else { $null } }
        default     { $null }
    }
    if ($null -ne $targetPanel) {
        try {
            $targetPanel.Opacity = 0
            $fadeIn = New-Object System.Windows.Media.Animation.DoubleAnimation
            $fadeIn.From = 0
            $fadeIn.To = 1
            $fadeIn.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(150))
            $targetPanel.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fadeIn)
        } catch { $targetPanel.Opacity = 1 }
    }
}

#endregion

#region Help Content
$script:HelpContent = @{
    Overview = @"
WSUS MANAGER OVERVIEW

A toolkit for deploying and managing Windows Server Update Services with SQL Server Express 2022.

FEATURES
• Modern dark-themed GUI with auto-refresh
• Air-gapped network support (export/import)
• Automated sync, cleanup, and deep cleanup
• Smart decline: superseded, >6mo old, Preview/Beta, ARM64, 23H2 and lower, Edge non-stable, Office 365/2019/LTSC 2021 (keeps 2024), WSL
• Default products: Windows 11, Server 2019, .NET Framework, Edge, Defender, Office 2016, SQL Server 2022, Security Essentials, Visual Studio 2022, Exchange 2019
• DNS preflight check before sync
• Keyboard shortcuts (Ctrl+D, Ctrl+S, Ctrl+H, Ctrl+R)

QUICK START
1. Run WsusManager.exe as Administrator
2. Use 'Install WSUS' for fresh installation
3. Dashboard shows real-time status
4. Server Mode auto-detects Online vs Air-Gap based on internet access

REQUIREMENTS
• Windows Server 2019+
• PowerShell 5.1+
• SQL Server Express 2022
• 150 GB+ disk space

PATHS
• Content: C:\WSUS\
• SQL Installers: C:\WSUS\SQLDB\
• Logs: C:\WSUS\Logs\
"@

    Dashboard = @"
DASHBOARD GUIDE

Four status cards with 30-second auto-refresh.

SERVICES CARD
• Green: All 3 running (SQL, WSUS, IIS)
• Orange: Partial
• Red: Critical services stopped

DATABASE CARD
• Shows SUSDB vs 10GB SQL Express limit
• Green: <7GB | Orange: 7-9GB | Red: >9GB

DISK CARD
• Green: >50GB | Orange: 10-50GB | Red: <10GB (recommend 150 GB+ total)

TASK CARD
• Green: Scheduled task ready
• Orange: Not configured

QUICK ACTIONS
• Deep Diagnostics - Health, content, IIS, SQL networking, BITS, ACL, and event-log checks with safe auto-repair
• Deep Cleanup - Aggressive cleanup
• Online Sync - Sync with Microsoft
• Start Services - Start all services
"@

    Operations = @"
OPERATIONS GUIDE

SETUP
• Install WSUS - Fresh installation with SQL Express
• Restore DB - Restore SUSDB from backup

TRANSFER
• Export (Online) - Full export to USB
• Import (Air-Gap) - Import from external media

MAINTENANCE
• Online Sync (Online only) - Sync, auto-decline, approve recent x64 updates, deep cleanup, backup
• Schedule Task (Online only) - Create/update the sync scheduled task
• Deep Cleanup - Remove obsolete, shrink database

DIAGNOSTICS
• Deep Diagnostics - Comprehensive health, content/download, IIS, SQL networking, BITS, ACL, and event-log checks with safe auto-repair
• Reset Content - Re-verify content files after import
"@

    AirGap = @"
AIR-GAP WORKFLOW

Two-server model for disconnected networks:
• Online WSUS: Internet-connected
• Air-Gap WSUS: Disconnected

WORKFLOW
1. On Online server: Run Online Sync, then Export
2. Transfer USB to air-gap network
3. On Air-Gap server: Import, then Restore DB

EXPORT
• Full export: Complete DB + all content files

TIPS
• Use USB 3.0 formatted as NTFS
• Scan USB per security policy
• Keep servers synchronized
"@

    Troubleshooting = @"
TROUBLESHOOTING

SERVICES WON'T START
1. Start SQL Server first
2. Use 'Start Services' button
3. Check Event Viewer
4. Run Diagnostics

DATABASE OFFLINE
• Start SQL Server Express service
• Check disk space
• Run Diagnostics

DATABASE >9 GB
• Run Deep Cleanup
• Decline unneeded updates
• Run Online Sync

CLIENTS NOT UPDATING
• Verify GPO (gpresult /h)
• Run gpupdate /force
• Check ports 8530/8531
• Verify WSUS URL in registry

LOGS
• App: C:\WSUS\Logs\
• WSUS: C:\Program Files\Update Services\LogFiles\
• IIS: C:\inetpub\logs\LogFiles\
"@
}

function Show-Help {
    param([string]$Topic = "Overview")
    Show-Panel "Help" "Help" "BtnHelp"
    $controls.HelpTitle.Text = $Topic
    $controls.HelpText.Text = $script:HelpContent[$Topic]
}
#endregion

#region Dialogs
function Show-ExportDialog {
    $result = @{ Cancelled = $true; DestinationPath = "" }

    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ExportDialog")
    $dlg.Title = "Export to Media"
    $dlg.Width = 480
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    Set-DialogAutoFit $dlg
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Export WSUS Data"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = $script:BrushText1
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    $radioPanel = New-Object System.Windows.Controls.StackPanel
    $radioPanel.Orientation = "Horizontal"
    $radioPanel.Margin = "0,0,0,12"

    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full Export"
    $radioFull.Foreground = $script:BrushText1
    $radioFull.IsChecked = $true
    $radioFull.Margin = "0,0,20,0"
    $radioPanel.Children.Add($radioFull)
    $stack.Children.Add($radioPanel)

    $destLbl = New-Object System.Windows.Controls.TextBlock
    $destLbl.Text = "Destination:"
    $destLbl.Foreground = $script:BrushText2
    $destLbl.Margin = "0,0,0,6"
    $stack.Children.Add($destLbl)

    $destPanel = New-Object System.Windows.Controls.DockPanel
    $destPanel.Margin = "0,0,0,20"

    $destBtn = New-Object System.Windows.Controls.Button
    $destBtn.Content = "Browse"
    $destBtn.Padding = "10,4"
    $destBtn.Background = $script:BrushBgCard
    $destBtn.Foreground = $script:BrushText1
    $destBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($destBtn, "Right")
    $destPanel.Children.Add($destBtn)

    $destTxt = New-Object System.Windows.Controls.TextBox
    $destTxt.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ExportDestinationTextBox")
    $destTxt.Margin = "0,0,8,0"
    $destTxt.Background = $script:BrushBgCard
    $destTxt.Foreground = $script:BrushText1
    $destTxt.Padding = "8,4"
    $destPanel.Children.Add($destTxt)

    $destBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        try { if ($fbd.ShowDialog() -eq "OK") { $destTxt.Text = $fbd.SelectedPath } }
        finally { $fbd.Dispose() }
    })
    $stack.Children.Add($destPanel)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $exportBtn = New-Object System.Windows.Controls.Button
    $exportBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ExportButton")
    $exportBtn.Content = "Export"
    $exportBtn.Padding = "12,8"
    $exportBtn.Background = $script:BrushBlue
    $exportBtn.Foreground = $script:BrushText1
    $exportBtn.BorderThickness = 0
    $exportBtn.Margin = "0,0,8,0"
    $exportBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($destTxt.Text)) {
            Show-WsusPopup -Message "Select destination folder." -Title "Export" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $result.Cancelled = $false
        $result.DestinationPath = $destTxt.Text
        $dlg.Close()
    })
    $btnPanel.Children.Add($exportBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() })
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-ImportDialog {
    $result = @{ Cancelled = $true; SourcePath = ""; DestinationPath = "C:\WSUS" }

    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ImportDialog")
    $dlg.Title = "Import from Media"
    $dlg.Width = 480
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    Set-DialogAutoFit $dlg
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Import WSUS Data"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = $script:BrushText1
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    # Source folder section
    $srcLbl = New-Object System.Windows.Controls.TextBlock
    $srcLbl.Text = "Source folder (external media):"
    $srcLbl.Foreground = $script:BrushText2
    $srcLbl.Margin = "0,0,0,6"
    $stack.Children.Add($srcLbl)

    $srcPanel = New-Object System.Windows.Controls.DockPanel
    $srcPanel.Margin = "0,0,0,16"

    $srcBtn = New-Object System.Windows.Controls.Button
    $srcBtn.Content = "Browse"
    $srcBtn.Padding = "10,4"
    $srcBtn.Background = $script:BrushBgCard
    $srcBtn.Foreground = $script:BrushText1
    $srcBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($srcBtn, "Right")
    $srcPanel.Children.Add($srcBtn)

    $srcTxt = New-Object System.Windows.Controls.TextBox
    $srcTxt.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ImportSourceTextBox")
    $srcTxt.Margin = "0,0,8,0"
    $srcTxt.Background = $script:BrushBgCard
    $srcTxt.Foreground = $script:BrushText1
    $srcTxt.Padding = "8,4"
    $srcPanel.Children.Add($srcTxt)

    $srcBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select source folder containing WSUS export data"
        try { if ($fbd.ShowDialog() -eq "OK") { $srcTxt.Text = $fbd.SelectedPath } }
        finally { $fbd.Dispose() }
    })
    $stack.Children.Add($srcPanel)

    # Destination folder section
    $dstLbl = New-Object System.Windows.Controls.TextBlock
    $dstLbl.Text = "Destination folder (WSUS server):"
    $dstLbl.Foreground = $script:BrushText2
    $dstLbl.Margin = "0,0,0,6"
    $stack.Children.Add($dstLbl)

    $dstPanel = New-Object System.Windows.Controls.DockPanel
    $dstPanel.Margin = "0,0,0,20"

    $dstBtn = New-Object System.Windows.Controls.Button
    $dstBtn.Content = "Browse"
    $dstBtn.Padding = "10,4"
    $dstBtn.Background = $script:BrushBgCard
    $dstBtn.Foreground = $script:BrushText1
    $dstBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($dstBtn, "Right")
    $dstPanel.Children.Add($dstBtn)

    $dstTxt = New-Object System.Windows.Controls.TextBox
    $dstTxt.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ImportDestinationTextBox")
    $dstTxt.Text = "C:\WSUS"
    $dstTxt.Margin = "0,0,8,0"
    $dstTxt.Background = $script:BrushBgCard
    $dstTxt.Foreground = $script:BrushText1
    $dstTxt.Padding = "8,4"
    $dstPanel.Children.Add($dstTxt)

    $dstBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select destination folder on WSUS server"
        $fbd.SelectedPath = $dstTxt.Text
        try { if ($fbd.ShowDialog() -eq "OK") { $dstTxt.Text = $fbd.SelectedPath } }
        finally { $fbd.Dispose() }
    })
    $stack.Children.Add($dstPanel)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $importBtn = New-Object System.Windows.Controls.Button
    $importBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ImportButton")
    $importBtn.Content = "Import"
    $importBtn.Padding = "12,8"
    $importBtn.Background = $script:BrushBlue
    $importBtn.Foreground = $script:BrushText1
    $importBtn.BorderThickness = 0
    $importBtn.Margin = "0,0,8,0"
    $importBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($srcTxt.Text)) {
            Show-WsusPopup -Message "Select source folder." -Title "Import" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($dstTxt.Text)) {
            Show-WsusPopup -Message "Select destination folder." -Title "Import" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $result.Cancelled = $false
        $result.SourcePath = $srcTxt.Text
        $result.DestinationPath = $dstTxt.Text
        $dlg.Close()
    })
    $btnPanel.Children.Add($importBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() })
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-RestoreDialog {
    $result = @{ Cancelled = $true; BackupPath = "" }
    $backupPath = $script:ContentPath
    $backupFiles = @()
    if (Test-Path $backupPath) {
        $backupFiles = Get-ChildItem -Path $backupPath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    }

    $dlgShell = New-WsusDialog -Title "Restore Database" -Width 520 -Height 420 -Owner $script:window -AutomationId "RestoreDialog"
    $dlg = $dlgShell.Window
    Set-DialogAutoFit $dlg
    $stack = $dlgShell.ContentPanel

    $title = New-WsusDialogLabel -Text "Restore WSUS Database"
    $title.FontSize = 14
    $title.FontWeight = 'Bold'
    $title.Margin = '0,0,0,8'
    $stack.Children.Add($title) | Out-Null

    $restoreWarning = New-WsusDialogLabel -Text "This will permanently replace the current SUSDB database. Create a backup first." -IsSecondary $true
    $restoreWarning.Foreground = $script:BrushRed
    $restoreWarning.TextWrapping = "Wrap"
    $restoreWarning.Margin = "0,0,0,12"
    $stack.Children.Add($restoreWarning) | Out-Null

    $stack.Children.Add((New-WsusDialogLabel -Text "Backup file:" -IsSecondary $true)) | Out-Null
    $filePanel = New-Object System.Windows.Controls.DockPanel
    $filePanel.Margin = "0,0,0,12"
    $browseBtn = New-WsusDialogButton -Text "Browse"
    [System.Windows.Controls.DockPanel]::SetDock($browseBtn, "Right")
    $fileTxt = New-WsusDialogTextBox -InitialText $(if ($backupFiles.Count -gt 0) { $backupFiles[0].FullName } else { "" }) -AutomationId "RestoreFileTextBox"
    $fileTxt.Margin = "0,0,8,0"
    $browseBtn.Add_Click({
        $ofd = New-Object Microsoft.Win32.OpenFileDialog
        $ofd.Filter = "Backup Files (*.bak)|*.bak|All Files (*.*)|*.*"
        $ofd.InitialDirectory = $backupPath
        if ($ofd.ShowDialog() -eq $true) { $fileTxt.Text = $ofd.FileName }
    })
    $filePanel.Children.Add($browseBtn) | Out-Null
    $filePanel.Children.Add($fileTxt) | Out-Null
    $stack.Children.Add($filePanel) | Out-Null

    if ($backupFiles.Count -gt 0) {
        $recentLbl = New-WsusDialogLabel -Text "Recent backups found in ${backupPath}:" -IsSecondary $true
        $recentLbl.Margin = "0,0,0,6"
        $stack.Children.Add($recentLbl) | Out-Null

        $listBox = New-Object System.Windows.Controls.ListBox
        $listBox.MaxHeight = 100
        $listBox.Background = $script:BrushBgCard
        $listBox.Foreground = $script:BrushText1
        $listBox.BorderThickness = 0
        $listBox.Margin = "0,0,0,12"

        foreach ($bf in ($backupFiles | Select-Object -First 5)) {
            $size = [math]::Round($bf.Length / 1MB, 1)
            $item = "$($bf.Name) - $($bf.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) - ${size}MB"
            $listBox.Items.Add($item) | Out-Null
        }
        $listBox.SelectedIndex = 0
        $listBox.Add_SelectionChanged({
            if ($listBox.SelectedIndex -ge 0 -and $listBox.SelectedIndex -lt $backupFiles.Count) {
                $fileTxt.Text = $backupFiles[$listBox.SelectedIndex].FullName
            }
        })
        $stack.Children.Add($listBox) | Out-Null
    } else {
        $noFilesLbl = New-WsusDialogLabel -Text "No backup files found in $backupPath. Use Browse to select a backup file." -IsSecondary $true
        $noFilesLbl.Foreground = $script:BrushOrange
        $noFilesLbl.TextWrapping = "Wrap"
        $noFilesLbl.Margin = "0,0,0,12"
        $stack.Children.Add($noFilesLbl) | Out-Null
    }

    $warnLbl = New-WsusDialogLabel -Text "Warning: This will replace the current SUSDB database!" -IsSecondary $true
    $warnLbl.Foreground = $script:BrushRed
    $warnLbl.FontWeight = "SemiBold"
    $warnLbl.Margin = "0,0,0,16"
    $stack.Children.Add($warnLbl) | Out-Null

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $restoreBtn = New-WsusDialogButton -Text "Restore" -Margin "0,0,8,0"
    $restoreBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "RestoreButton")
    $restoreBtn.Background = $script:BrushRed
    $restoreBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($fileTxt.Text)) {
            Show-WsusPopup -Message "Select a backup file." -Title "Restore" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        if (-not (Test-Path $fileTxt.Text)) {
            Show-WsusPopup -Message "Backup file not found: $($fileTxt.Text)" -Title "Restore" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
            return
        }
        $confirm = Show-WsusPopup -Message "Are you sure you want to restore from:`n$($fileTxt.Text)`n`nThis will replace the current database!" -Title "Confirm Restore" -Button ([System.Windows.MessageBoxButton]::YesNo) -Icon ([System.Windows.MessageBoxImage]::Warning)
        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            $result.Cancelled = $false
            $result.BackupPath = $fileTxt.Text
            $dlg.Close()
        }
    })
    $btnPanel.Children.Add($restoreBtn) | Out-Null

    $cancelBtn = New-WsusDialogButton -Text "Cancel"
    $cancelBtn.Add_Click({ $dlg.Close() })
    $btnPanel.Children.Add($cancelBtn) | Out-Null

    $stack.Children.Add($btnPanel) | Out-Null
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-MaintenanceDialog {
    $result = @{ Cancelled = $true; Profile = ""; ExportPath = ""; SelectedProducts = @() }

    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "MaintenanceDialog")
    $dlg.Title = "Online Sync"
    $dlg.Width = 520
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    Set-DialogAutoFit $dlg
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    # === TabControl with dark theme ===
    # Build TabControl via XAML for reliable PS5.1 dark theme styling
    $tabXaml = @'
<TabControl xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            Background="#0D1117" BorderBrush="#30363D" BorderThickness="1" Margin="0,0,0,16">
    <TabControl.Resources>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#161B22"/>
            <Setter Property="Foreground" Value="#6E7681"/>
            <Setter Property="BorderBrush" Value="#30363D"/>
            <Setter Property="BorderThickness" Value="1,1,1,0"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,2,0"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#0D1117"/>
                    <Setter Property="Foreground" Value="#58A6FF"/>
                    <Setter Property="BorderBrush" Value="#58A6FF"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </TabControl.Resources>
</TabControl>
'@
    $tabControl = [System.Windows.Markup.XamlReader]::Parse($tabXaml)

    # --- Tab 1: Profile ---
    $tabProfile = New-Object System.Windows.Controls.TabItem
    $tabProfile.Header = "Profile"

    $profileStack = New-Object System.Windows.Controls.StackPanel
    $profileStack.Margin = "12"

    $profileTitle = New-Object System.Windows.Controls.TextBlock
    $profileTitle.Text = "Select Sync Profile"
    $profileTitle.FontSize = 14
    $profileTitle.FontWeight = "Bold"
    $profileTitle.Foreground = $script:BrushText1
    $profileTitle.Margin = "0,0,0,16"
    $profileStack.Children.Add($profileTitle)

    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full Sync"
    $radioFull.Foreground = $script:BrushText1
    $radioFull.Margin = "0,0,0,4"
    $radioFull.IsChecked = $true
    $profileStack.Children.Add($radioFull)

    $fullDesc = New-Object System.Windows.Controls.TextBlock
    $fullDesc.Text = "Sync > Cleanup > Ultimate Cleanup > Backup > Export"
    $fullDesc.Foreground = $script:BrushText2
    $fullDesc.FontSize = 12
    $fullDesc.Margin = "20,0,0,12"
    $profileStack.Children.Add($fullDesc)

    $radioQuick = New-Object System.Windows.Controls.RadioButton
    $radioQuick.Content = "Quick Sync"
    $radioQuick.Foreground = $script:BrushText1
    $radioQuick.Margin = "0,0,0,4"
    $profileStack.Children.Add($radioQuick)

    $quickDesc = New-Object System.Windows.Controls.TextBlock
    $quickDesc.Text = "Sync > Cleanup > Backup (skip heavy cleanup)"
    $quickDesc.Foreground = $script:BrushText2
    $quickDesc.FontSize = 12
    $quickDesc.Margin = "20,0,0,12"
    $profileStack.Children.Add($quickDesc)

    $radioSync = New-Object System.Windows.Controls.RadioButton
    $radioSync.Content = "Sync Only"
    $radioSync.Foreground = $script:BrushText1
    $radioSync.Margin = "0,0,0,4"
    $profileStack.Children.Add($radioSync)

    $syncDesc = New-Object System.Windows.Controls.TextBlock
    $syncDesc.Text = "Synchronize and approve updates only (no export)"
    $syncDesc.Foreground = $script:BrushText2
    $syncDesc.FontSize = 12
    $syncDesc.Margin = "20,0,0,16"
    $profileStack.Children.Add($syncDesc)

    $tabProfile.Content = $profileStack
    $tabControl.Items.Add($tabProfile)

    # --- Tab 2: Products ---
    $tabProducts = New-Object System.Windows.Controls.TabItem
    $tabProducts.Header = "Products"

    $productsStack = New-Object System.Windows.Controls.StackPanel
    $productsStack.Margin = "12"

    $prodTitle = New-Object System.Windows.Controls.TextBlock
    $prodTitle.Text = "Products to Sync"
    $prodTitle.FontSize = 14
    $prodTitle.FontWeight = "Bold"
    $prodTitle.Foreground = $script:BrushText1
    $prodTitle.Margin = "0,0,0,8"
    $productsStack.Children.Add($prodTitle)

    # Dynamically read products from WSUS, fall back to saved defaults.
    # Always include the user's saved/default products even when WSUS API
    # returns a list -- otherwise the defaults look "lost" until WSUS has
    # committed the same titles (after a successful sync).
    $productNames = $script:SyncProducts
    $productsFromWsus = $false
    try {
        Add-Type -Path "$env:ProgramFiles\Update Services\Api\Microsoft.UpdateServices.Administration.dll" -ErrorAction SilentlyContinue
        $wsusApi = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost",$false,8530)
        if ($wsusApi) {
            $wsusProducts = $wsusApi.GetSubscription().GetUpdateCategories() | Where-Object { $_.Type -eq 'Product' -and -not $_.ParentCategory }
            if ($wsusProducts.Count -gt 0) {
                $wsusNames = @($wsusProducts | ForEach-Object { $_.Title } | Sort-Object -Unique)
                # Merge: WSUS server's known products + any saved/default
                # products not already in the WSUS list, so the user's
                # selections always show up as checkboxes.
                $merged = @($wsusNames)
                foreach ($def in $script:SyncProducts) {
                    if (-not ($merged | Where-Object { $_ -eq $def })) { $merged += $def }
                }
                $productNames = @($merged | Sort-Object -Unique)
                $productsFromWsus = $true
            }
        }
    } catch { Write-Verbose $_.Exception.Message }

    # ScrollViewer for large product lists
    $productScroll = New-Object System.Windows.Controls.ScrollViewer
    $productScroll.MaxHeight = 280
    $productScroll.VerticalScrollBarVisibility = "Auto"
    $productScroll.Margin = "0,0,0,8"

    $productInnerStack = New-Object System.Windows.Controls.StackPanel
    $productCheckBoxes = @{}
    foreach ($prod in $productNames) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $prod
        $cb.Foreground = $script:BrushText1
        $cb.Margin = "0,0,0,4"
        $cb.IsChecked = @($script:SyncProducts | Where-Object { Test-WsusSelectedProductTitle -SelectedProduct $_ -AvailableTitle $prod }).Count -gt 0
        $productCheckBoxes[$prod] = $cb
        $productInnerStack.Children.Add($cb)
    }
    $productScroll.Content = $productInnerStack
    $productsStack.Children.Add($productScroll)

    if (-not $productsFromWsus) {
        $prodNote = New-Object System.Windows.Controls.TextBlock
        $prodNote.Text = "Note: Product list will mirror WSUS after first sync completes."
        $prodNote.Foreground = $script:BrushText2
        $prodNote.FontSize = 11
        $prodNote.Margin = "0,4,0,0"
        $prodNote.TextWrapping = "Wrap"
        $productsStack.Children.Add($prodNote)
    }

    $prodSubNote = New-Object System.Windows.Controls.TextBlock
    $prodSubNote.Text = "Note: keep .NET Framework enabled for Windows 11 / Server 2019 servicing. 25H2 stays available for manual review only."
    $prodSubNote.Foreground = $script:BrushText2
    $prodSubNote.FontSize = 11
    $prodSubNote.Margin = "0,4,0,0"
    $prodSubNote.TextWrapping = "Wrap"
    $productsStack.Children.Add($prodSubNote)

    $tabProducts.Content = $productsStack
    $tabControl.Items.Add($tabProducts)

    # --- Tab 3: Export ---
    $tabExport = New-Object System.Windows.Controls.TabItem
    $tabExport.Header = "Export"

    $exportStack = New-Object System.Windows.Controls.StackPanel
    $exportStack.Margin = "12"

    $exportTitle = New-Object System.Windows.Controls.TextBlock
    $exportTitle.Text = "Export Settings (optional)"
    $exportTitle.FontSize = 14
    $exportTitle.FontWeight = "Bold"
    $exportTitle.Foreground = $script:BrushText1
    $exportTitle.Margin = "0,0,0,12"
    $exportStack.Children.Add($exportTitle)

    # Full Export Path
    $exportLabel = New-Object System.Windows.Controls.TextBlock
    $exportLabel.Text = "Full Export Path (backup + all content):"
    $exportLabel.Foreground = $script:BrushText2
    $exportLabel.FontSize = 12
    $exportLabel.Margin = "0,0,0,4"
    $exportStack.Children.Add($exportLabel)

    $exportPanel = New-Object System.Windows.Controls.DockPanel
    $exportPanel.Margin = "0,0,0,12"

    $exportBrowse = New-Object System.Windows.Controls.Button
    $exportBrowse.Content = "..."
    $exportBrowse.Width = 30
    $exportBrowse.Background = $script:BrushBgCard
    $exportBrowse.Foreground = $script:BrushText1
    $exportBrowse.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($exportBrowse, "Right")
    $exportPanel.Children.Add($exportBrowse)

    $exportBox = New-Object System.Windows.Controls.TextBox
    $exportBox.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SyncFullExportTextBox")
    $exportBox.Background = $script:BrushBgCard
    $exportBox.Foreground = $script:BrushText1
    $exportBox.BorderThickness = 0
    $exportBox.Padding = "8,6"
    $exportBox.Margin = "0,0,4,0"
    $exportPanel.Children.Add($exportBox)

    $exportStack.Children.Add($exportPanel)

    # Export info note
    $exportNote = New-Object System.Windows.Controls.TextBlock
    $exportNote.Text = "Leave paths empty to skip export after sync."
    $exportNote.Foreground = $script:BrushText2
    $exportNote.FontSize = 11
    $exportNote.TextWrapping = "Wrap"
    $exportStack.Children.Add($exportNote)

    $tabExport.Content = $exportStack
    $tabControl.Items.Add($tabExport)

    $stack.Children.Add($tabControl)

    # Browse button handlers
    $exportBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select full export destination (network share or local path)"
        try {
            if ($fbd.ShowDialog() -eq "OK") {
                $exportBox.Text = $fbd.SelectedPath
            }
        } finally { $fbd.Dispose() }
    })

    # Button panel (outside tabs)
    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $runBtn = New-Object System.Windows.Controls.Button
    $runBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "RunSyncButton")
    $runBtn.Content = "Run Sync"
    $runBtn.Padding = "12,8"
    $runBtn.Background = $script:BrushBlue
    $runBtn.Foreground = $script:BrushText1
    $runBtn.BorderThickness = 0
    $runBtn.Margin = "0,0,8,0"
    $runBtn.Add_Click({
        $result.Cancelled = $false
        if ($radioFull.IsChecked) { $result.Profile = "Full" }
        elseif ($radioQuick.IsChecked) { $result.Profile = "Quick" }
        else { $result.Profile = "SyncOnly" }
        $result.ExportPath = $exportBox.Text.Trim()
        $result.SelectedProducts = @()
        foreach ($prod in $productNames) {
            if ($productCheckBoxes[$prod].IsChecked) { $result.SelectedProducts += $prod }
        }
        if ($result.SelectedProducts.Count -eq 0) {
            Show-WsusPopup -Message "Select at least one product to sync." -Title "Validation" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $script:SyncProducts = $result.SelectedProducts
        Save-Settings
        $dlg.Close()
    })
    $btnPanel.Children.Add($runBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() })
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-ScheduleTaskDialog {
    <#
    .SYNOPSIS
        Displays the Schedule Task dialog for configuring monthly maintenance automation.

    .DESCRIPTION
        Creates a WPF modal dialog using XAML for reliable dark theme styling.
        Configures: Schedule type, day, time, maintenance profile, and credentials.

    .OUTPUTS
        Hashtable with: Cancelled, Schedule, DayOfWeek, DayOfMonth, Time, Profile, RunAsUser, Password
    #>

    # Result object - modified by button click handlers
    $script:ScheduleDialogResult = @{
        Cancelled = $true
        Schedule = "Weekly"
        DayOfWeek = "Tuesday"
        DayOfMonth = 1
        Time = "23:00"
        Profile = "Full"
        RunAsUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Password = ""
    }

    # =========================================================================
    # XAML-BASED DIALOG WITH DARK THEME
    # =========================================================================
    # Using XAML instead of programmatic control creation allows for complete
    # control over ComboBox styling via explicit ControlTemplates. This solves
    # the white-on-white text issue that occurs with native Windows theming.
    # =========================================================================
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:automation="clr-namespace:System.Windows.Automation;assembly=PresentationCore"
        Title="Schedule Online Sync" Width="480" Height="560"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#0D1117"
        automation:AutomationProperties.AutomationId="ScheduleDialog">
    <Window.Resources>
        <!-- Dark theme colors -->
        <SolidColorBrush x:Key="BgDark" Color="#0D1117"/>
        <SolidColorBrush x:Key="BgMid" Color="#21262D"/>
        <SolidColorBrush x:Key="BorderColor" Color="#30363D"/>
        <SolidColorBrush x:Key="TextColor" Color="#E6EDF3"/>
        <SolidColorBrush x:Key="LabelColor" Color="#8B949E"/>
        <SolidColorBrush x:Key="AccentColor" Color="#58A6FF"/>

        <!-- Dark ComboBox Style with custom template -->
        <Style x:Key="DarkComboBox" TargetType="ComboBox">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="BorderBrush" Value="#30363D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="2">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="30"/>
                                    </Grid.ColumnDefinitions>
                                    <ContentPresenter Grid.Column="0"
                                        Content="{TemplateBinding SelectionBoxItem}"
                                        ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                        VerticalAlignment="Center"
                                        Margin="{TemplateBinding Padding}"/>
                                    <Path Grid.Column="1" Data="M0,0 L4,4 L8,0" Stroke="#E6EDF3"
                                          StrokeThickness="1.5" HorizontalAlignment="Center"
                                          VerticalAlignment="Center"/>
                                </Grid>
                            </Border>
                            <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom"
                                   AllowsTransparency="True" Focusable="False">
                                <Border Background="#21262D" BorderBrush="#30363D"
                                        BorderThickness="1" MaxHeight="200">
                                    <ScrollViewer>
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                            <ToggleButton Grid.ColumnSpan="2" Opacity="0"
                                IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Dark ComboBoxItem Style -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="Padding" Value="8,4"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#58A6FF"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#58A6FF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Dark TextBox Style -->
        <Style x:Key="DarkTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="BorderBrush" Value="#30363D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="#E6EDF3"/>
        </Style>

        <!-- Dark PasswordBox Style -->
        <Style x:Key="DarkPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="BorderBrush" Value="#30363D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="#E6EDF3"/>
        </Style>
    </Window.Resources>

    <StackPanel Margin="20">
        <!-- Title -->
        <TextBlock Text="Create Scheduled Task" FontSize="14" FontWeight="Bold"
                   Foreground="#E6EDF3" Margin="0,0,0,8"/>
        <TextBlock Text="Recommended: Weekly on Saturday at 02:00" FontSize="12"
                   Foreground="#8B949E" Margin="0,0,0,16"/>

        <!-- Schedule Type -->
        <TextBlock Text="Schedule:" Foreground="#8B949E" Margin="0,0,0,4"/>
        <ComboBox x:Name="ScheduleCombo" Style="{StaticResource DarkComboBox}" Margin="0,0,0,12"
                  automation:AutomationProperties.AutomationId="ScheduleComboBox">
            <ComboBoxItem Content="Weekly" IsSelected="True"/>
            <ComboBoxItem Content="Monthly"/>
            <ComboBoxItem Content="Daily"/>
        </ComboBox>

        <!-- Day of Week (visible for Weekly) -->
        <StackPanel x:Name="DayOfWeekPanel" Margin="0,0,0,12">
            <TextBlock Text="Day of Week:" Foreground="#8B949E" Margin="0,0,0,4"/>
            <ComboBox x:Name="DowCombo" Style="{StaticResource DarkComboBox}">
                <ComboBoxItem Content="Sunday"/>
                <ComboBoxItem Content="Monday"/>
                <ComboBoxItem Content="Tuesday" IsSelected="True"/>
                <ComboBoxItem Content="Wednesday"/>
                <ComboBoxItem Content="Thursday"/>
                <ComboBoxItem Content="Friday"/>
                <ComboBoxItem Content="Saturday"/>
            </ComboBox>
        </StackPanel>

        <!-- Day of Month (hidden by default) -->
        <StackPanel x:Name="DayOfMonthPanel" Visibility="Collapsed" Margin="0,0,0,12">
            <TextBlock Text="Day of Month (1-31):" Foreground="#8B949E" Margin="0,0,0,4"/>
            <TextBox x:Name="DomBox" Text="1" Style="{StaticResource DarkTextBox}"/>
        </StackPanel>

        <!-- Start Time -->
        <TextBlock Text="Start Time (HH:mm):" Foreground="#8B949E" Margin="0,0,0,4"/>
        <TextBox x:Name="TimeBox" Text="23:00" Style="{StaticResource DarkTextBox}" Margin="0,0,0,12"
                 automation:AutomationProperties.AutomationId="ScheduleTimeTextBox"/>

        <!-- Maintenance Profile -->
        <TextBlock Text="Maintenance Profile:" Foreground="#8B949E" Margin="0,0,0,4"/>
        <ComboBox x:Name="ProfileCombo" Style="{StaticResource DarkComboBox}" Margin="0,0,0,12"
                  automation:AutomationProperties.AutomationId="ScheduleProfileComboBox">
            <ComboBoxItem Content="Full" IsSelected="True"/>
            <ComboBoxItem Content="Quick"/>
            <ComboBoxItem Content="SyncOnly"/>
        </ComboBox>

        <!-- Credentials Section -->
        <TextBlock Text="Run As Credentials (for unattended execution):" Foreground="#8B949E"
                   FontSize="12" Margin="0,4,0,8"/>

        <TextBlock Text="Username (DOMAIN\user):" Foreground="#8B949E" Margin="0,0,0,4"/>
        <TextBox x:Name="UserBox" Style="{StaticResource DarkTextBox}" Margin="0,0,0,12"
                 automation:AutomationProperties.AutomationId="ScheduleUserTextBox"/>

        <TextBlock Text="Password:" Foreground="#8B949E" Margin="0,0,0,4"/>
        <PasswordBox x:Name="PassBox" Style="{StaticResource DarkPasswordBox}" Margin="0,0,0,16"
                     automation:AutomationProperties.AutomationId="SchedulePasswordBox"/>

        <!-- Buttons -->
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCreate" Content="Create Task" Padding="12,8"
                    Background="#58A6FF" Foreground="#E6EDF3" BorderThickness="0" Margin="0,0,8,0"
                    automation:AutomationProperties.AutomationId="CreateScheduleButton"/>
            <Button x:Name="BtnCancel" Content="Cancel" Padding="12,8"
                    Background="#21262D" Foreground="#E6EDF3" BorderThickness="0"
                    automation:AutomationProperties.AutomationId="CancelScheduleButton"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    # Parse XAML and create window
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader)

    # Set owner if available
    if ($null -ne $script:window) {
        $dlg.Owner = $script:window
    }

    # Get control references
    $scheduleCombo = $dlg.FindName("ScheduleCombo")
    $dowPanel = $dlg.FindName("DayOfWeekPanel")
    $domPanel = $dlg.FindName("DayOfMonthPanel")
    $dowCombo = $dlg.FindName("DowCombo")
    $domBox = $dlg.FindName("DomBox")
    $timeBox = $dlg.FindName("TimeBox")
    $profileCombo = $dlg.FindName("ProfileCombo")
    $userBox = $dlg.FindName("UserBox")
    $passBox = $dlg.FindName("PassBox")
    $btnCreate = $dlg.FindName("BtnCreate")
    $btnCancel = $dlg.FindName("BtnCancel")

    # Default username to currently logged-in user
    $userBox.Text = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # ESC key closes dialog
    $dlg.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $sender.Close() }
    })

    # Schedule type change - toggle day panels
    $scheduleCombo.Add_SelectionChanged({
        $selected = $scheduleCombo.SelectedItem.Content
        if ($selected -eq "Monthly") {
            $dowPanel.Visibility = "Collapsed"
            $domPanel.Visibility = "Visible"
        } elseif ($selected -eq "Weekly") {
            $dowPanel.Visibility = "Visible"
            $domPanel.Visibility = "Collapsed"
        } else {
            $dowPanel.Visibility = "Collapsed"
            $domPanel.Visibility = "Collapsed"
        }
    })

    # Create button click
    $btnCreate.Add_Click({
        # Validate time format
        $timeVal = $timeBox.Text.Trim()
        if ($timeVal -notmatch '^\d{1,2}:\d{2}$') {
            Show-WsusPopup -Message "Invalid time format. Use HH:mm (e.g., 02:00)." -Title "Schedule" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }

        # Get schedule type
        $schedVal = $scheduleCombo.SelectedItem.Content

        # Validate day of month if Monthly
        $domVal = 1
        if ($schedVal -eq "Monthly") {
            if (-not [int]::TryParse($domBox.Text, [ref]$domVal) -or $domVal -lt 1 -or $domVal -gt 31) {
                Show-WsusPopup -Message "Day of month must be between 1 and 31." -Title "Schedule" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
                return
            }
        }

        # Validate credentials
        $userVal = $userBox.Text.Trim()
        $passVal = $passBox.Password
        if ([string]::IsNullOrWhiteSpace($userVal)) {
            Show-WsusPopup -Message "Username is required for scheduled task execution." -Title "Schedule" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($passVal)) {
            Show-WsusPopup -Message "Password is required for scheduled task execution.`n`nThe task needs credentials to run whether the user is logged on or not." -Title "Schedule" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }

        # Preflight: verify the specified user is an administrator
        try {
            $currentName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            if ($userVal -eq $currentName) {
                # Check current user's admin status directly
                $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            } else {
                # For other users, check local Administrators group membership
                $adminGroup = [ADSI]"WinNT://./Administrators,group"
                $members = @($adminGroup.Invoke("Members")) | ForEach-Object { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) }
                $shortName = $userVal.Split('\')[-1]
                $isAdmin = $shortName -in $members
            }
            if (-not $isAdmin) {
                Show-WsusPopup -Message "The user '$userVal' does not appear to be a member of the local Administrators group.`n`nThe scheduled task requires admin privileges to manage WSUS." -Title "Admin Required" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
                return
            }
        } catch {
            # If check fails (e.g., domain user lookup), warn but allow
            Write-Log "Admin check for '$userVal' inconclusive: $_"
        }

        # Store results
        $script:ScheduleDialogResult.Schedule = $schedVal
        $script:ScheduleDialogResult.DayOfWeek = $dowCombo.SelectedItem.Content
        $script:ScheduleDialogResult.DayOfMonth = $domVal
        $script:ScheduleDialogResult.Time = $timeVal
        $script:ScheduleDialogResult.Profile = $profileCombo.SelectedItem.Content
        $script:ScheduleDialogResult.RunAsUser = $userVal
        $script:ScheduleDialogResult.Password = $passVal
        $script:ScheduleDialogResult.Cancelled = $false
        $dlg.Close()
    })

    # Cancel button click
    $btnCancel.Add_Click({ $dlg.Close() })

    # Show dialog
    $dlg.ShowDialog() | Out-Null

    # Return result
    return $script:ScheduleDialogResult
}

function Show-TransferDialog {
    $result = @{ Cancelled = $true; SourcePath = ""; DestinationPath = "" }

    $dlgShell = New-WsusDialog -Title "Transfer Data" -Width 520 -Height 360 -Owner $script:window -AutomationId "TransferDialog"
    $dlg = $dlgShell.Window
    Set-DialogAutoFit $dlg
    $stack = $dlgShell.ContentPanel

    $title = New-WsusDialogLabel -Text "Transfer WSUS Data"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Margin = "0,0,0,16"
    $stack.Children.Add($title) | Out-Null

    $desc = New-WsusDialogLabel -Text "Uses robocopy to copy WSUS content between folders. Non-destructive -- only copies files, never deletes." -IsSecondary $true
    $desc.TextWrapping = "Wrap"
    $desc.Margin = "0,0,0,16"
    $stack.Children.Add($desc) | Out-Null

    $src = New-WsusFolderBrowser -LabelText "Source folder:" -InitialPath "" -Owner $dlg -AutomationId "TransferSourceBrowser"
    $src.TextBox.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "TransferSourceTextBox")
    $src.Panel.Margin = "0,0,0,12"
    $stack.Children.Add($src.Label) | Out-Null
    $stack.Children.Add($src.Panel) | Out-Null

    $dst = New-WsusFolderBrowser -LabelText "Destination folder:" -InitialPath "" -Owner $dlg -AutomationId "TransferDestBrowser"
    $dst.TextBox.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "TransferDestTextBox")
    $dst.Panel.Margin = "0,0,0,12"
    $stack.Children.Add($dst.Label) | Out-Null
    $stack.Children.Add($dst.Panel) | Out-Null

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $runBtn = New-WsusDialogButton -Text "Start Transfer" -IsPrimary $true -Margin "0,0,8,0"
    $runBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "StartTransferButton")
    $runBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($src.TextBox.Text)) {
            Show-WsusPopup -Message "Select a source folder." -Title "Transfer" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        if (-not (Test-Path $src.TextBox.Text)) {
            Show-WsusPopup -Message "Source folder not found: $($src.TextBox.Text)" -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($dst.TextBox.Text)) {
            Show-WsusPopup -Message "Select a destination folder." -Title "Transfer" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $result.Cancelled = $false
        $result.SourcePath = $src.TextBox.Text
        $result.DestinationPath = $dst.TextBox.Text
        $dlg.Close()
    })
    $btnPanel.Children.Add($runBtn) | Out-Null

    $cancelBtn = New-WsusDialogButton -Text "Cancel"
    $cancelBtn.Add_Click({ $dlg.Close() })
    $btnPanel.Children.Add($cancelBtn) | Out-Null

    $stack.Children.Add($btnPanel) | Out-Null
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SettingsDialog")
    $dlg.Title = "Settings"
    $dlg.Width = 480
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    Set-DialogAutoFit $dlg

    # Close dialog on ESC key
    $dlg.Add_KeyDown({
        param($sender, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $sender.Close() }
    })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $lbl1 = New-Object System.Windows.Controls.TextBlock
    $lbl1.Text = "WSUS Content Path:"
    $lbl1.Foreground = $script:BrushText2
    $lbl1.Margin = "0,0,0,4"
    $stack.Children.Add($lbl1)

    $txt1 = New-Object System.Windows.Controls.TextBox
    $txt1.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SettingsContentPathTextBox")
    $txt1.Text = $script:ContentPath
    $txt1.Margin = "0,0,0,12"
    $txt1.Background = $script:BrushBgCard
    $txt1.Foreground = $script:BrushText1
    $txt1.Padding = "8,4"
    $stack.Children.Add($txt1)

    $lbl2 = New-Object System.Windows.Controls.TextBlock
    $lbl2.Text = "SQL Instance:"
    $lbl2.Foreground = $script:BrushText2
    $lbl2.Margin = "0,0,0,4"
    $stack.Children.Add($lbl2)

    $txt2 = New-Object System.Windows.Controls.TextBox
    $txt2.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SettingsSqlInstanceTextBox")
    $txt2.Text = $script:SqlInstance
    $txt2.Margin = "0,0,0,16"
    $txt2.Background = $script:BrushBgCard
    $txt2.Foreground = $script:BrushText1
    $txt2.Padding = "8,4"
    $stack.Children.Add($txt2)

    # Notification Settings
    $notifSep = New-Object System.Windows.Controls.Separator
    $notifSep.Margin = "0,4,0,12"
    $notifSep.Background = $script:BrushBorder
    $stack.Children.Add($notifSep)

    $notifLbl = New-Object System.Windows.Controls.TextBlock
    $notifLbl.Text = "Notifications & Sound"
    $notifLbl.FontWeight = "SemiBold"
    $notifLbl.Foreground = $script:BrushText2
    $notifLbl.Margin = "0,0,0,8"
    $stack.Children.Add($notifLbl)

    $chkNotif = New-Object System.Windows.Controls.CheckBox
    $chkNotif.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SettingsNotificationCheckBox")
    $chkNotif.Content = "Show notification when operation completes"
    $chkNotif.Foreground = $script:BrushText1
    $chkNotif.IsChecked = $script:NotificationsEnabled
    $chkNotif.Margin = "0,0,0,6"
    $stack.Children.Add($chkNotif)

    $chkBeep = New-Object System.Windows.Controls.CheckBox
    $chkBeep.Content = "Play beep sound on completion"
    $chkBeep.Foreground = $script:BrushText1
    $chkBeep.IsChecked = $script:NotificationBeep
    $chkBeep.Margin = "0,0,0,4"
    $stack.Children.Add($chkBeep)

    $chkTray = New-Object System.Windows.Controls.CheckBox
    $chkTray.Content = "Minimize to system tray"
    $chkTray.Foreground = $script:BrushText1
    $chkTray.IsChecked = $script:TrayMinimize
    $chkTray.Margin = "0,0,0,16"
    $stack.Children.Add($chkTray)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $saveBtn = New-Object System.Windows.Controls.Button
    $saveBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SaveSettingsButton")
    $saveBtn.Content = "Save"
    $saveBtn.Padding = "12,8"
    $saveBtn.Background = $script:BrushBlue
    $saveBtn.Foreground = $script:BrushText1
    $saveBtn.BorderThickness = 0
    $saveBtn.Margin = "0,0,8,0"
    $saveBtn.Add_Click({
        $script:ContentPath = if($txt1.Text){$txt1.Text}else{"C:\WSUS"}
        $script:SqlInstance = if($txt2.Text){$txt2.Text}else{".\SQLEXPRESS"}
        $script:NotificationsEnabled = $chkNotif.IsChecked -eq $true
        $script:NotificationBeep = $chkBeep.IsChecked -eq $true
        $script:TrayMinimize = $chkTray.IsChecked -eq $true
        Save-Settings
        Invoke-DashboardRefreshSafe -Source "Settings Save"
        $dlg.Close()
    })
    $btnPanel.Children.Add($saveBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() })
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
}

#endregion

#region Operations
# Run operation with output to bottom log panel (stays on current view)
function Invoke-LogOperation {
    param([string]$Id, [string]$Title)

    if ($script:OperationRunning) {
        Show-WsusPopup -Message "An operation is already running. Please wait for it to complete or cancel it." -Title "Operation In Progress" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) -SuppressDuplicateSeconds 3 | Out-Null
        return
    }

    $dbOperations = @("restore", "cleanup", "diagnostics", "maintenance")
    if ($Id -in $dbOperations) {
        $sqlInstance = $script:SqlInstance
        $sqlcmd = Get-SqlCmdPath
        if (-not $sqlcmd) {
            Show-WsusPopup -Message "sqlcmd.exe not found. SQL Server does not appear to be installed.`n`nRun 'Install WSUS' first, or use 'Fix SQL Login' to troubleshoot." -Title "SQL Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
            Write-Log "PREFLIGHT FAIL: sqlcmd.exe not found for operation '$Id'"
            return
        }

        try {
            $errFile = [System.IO.Path]::GetTempFileName()
            & $sqlcmd -S $sqlInstance -E -C -Q "SELECT 1" 2>$errFile | Out-Null
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $errContent = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
                if (-not $errContent) { $errContent = "Exit code: $exitCode" }
                Remove-Item $errFile -Force -ErrorAction SilentlyContinue
                Show-WsusPopup -Message "Cannot connect to SQL Server at $sqlInstance using Windows Authentication.`n`n$errContent`n`nMake sure:`n- SQL Express service is running`n- You are a member of BUILTIN\Administrators or have sysadmin access`n`nUse 'Fix SQL Login' in the Setup menu to add your account." -Title "SQL Connection Failed" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
                Write-Log "PREFLIGHT FAIL: SQL connection to $sqlInstance failed (exit $exitCode): $errContent"
                return
            }
            Remove-Item $errFile -Force -ErrorAction SilentlyContinue
            Write-Log "PREFLIGHT OK: SQL connectivity verified ($sqlInstance) for operation '$Id'"
        } catch {
            Show-WsusPopup -Message "Cannot connect to SQL Server at $sqlInstance.`n`nError: $($_.Exception.Message)`n`nUse 'Fix SQL Login' in the Setup menu to add your account." -Title "SQL Connection Failed" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
            Write-Log "PREFLIGHT FAIL: $($_.Exception.Message)"
            return
        }
    }

    if ($script:ServerMode -eq "Air-Gap" -and $Id -in @("maintenance", "schedule")) {
        Show-WsusPopup -Message "This operation is only available on the Online WSUS server." -Title "Online Only" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) -SuppressDuplicateSeconds 3 | Out-Null
        return
    }

    Write-Log "Run-LogOp: $Id"

    $sr = $script:ScriptRoot
    $mgmt = Find-WsusScript -ScriptName "Invoke-WsusManagement.ps1" -ScriptRoot $sr
    $maint = Find-WsusScript -ScriptName "Invoke-WsusMonthlyMaintenance.ps1" -ScriptRoot $sr
    $taskModule = Find-WsusScript -ScriptName "WsusScheduledTask.psm1" -ScriptRoot $sr
    if (-not $taskModule) {
        $taskModule = Find-WsusScript -ScriptName "WsusScheduledTask.psm1" -ScriptRoot (Join-Path $sr "Modules")
    }
    if (-not $taskModule) {
        $parentModules = Join-Path (Split-Path $sr -Parent) "Modules"
        if (Test-Path (Join-Path $parentModules "WsusScheduledTask.psm1")) {
            $taskModule = Join-Path $parentModules "WsusScheduledTask.psm1"
        }
    }

    if ($Id -ne "schedule") {
        if (-not $mgmt) {
            Show-WsusPopup -Message "Cannot find Invoke-WsusManagement.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe" -Title "Script Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
            Write-Log "ERROR: Invoke-WsusManagement.ps1 not found in $sr or $sr\Scripts"
            return
        }
        if ($Id -eq "maintenance" -and -not $maint) {
            Show-WsusPopup -Message "Cannot find Invoke-WsusMonthlyMaintenance.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe" -Title "Script Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
            Write-Log "ERROR: Invoke-WsusMonthlyMaintenance.ps1 not found in $sr or $sr\Scripts"
            return
        }
    }

    if ($Id -eq "schedule" -and -not $taskModule) {
        Show-WsusPopup -Message "Cannot find WsusScheduledTask.psm1`n`nSearched in:`n- $sr`n- $sr\Scripts`n- $sr\Modules`n- $(Split-Path $sr -Parent)\Modules`n`nMake sure the Modules folder is in the same directory as WsusManager.exe" -Title "Module Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
        Write-Log "ERROR: WsusScheduledTask.psm1 not found"
        return
    }

    $operationPlan = $null
    $cmd = switch ($Id) {
        "install" {
            $installScript = Find-WsusScript -ScriptName "Install-WsusWithSqlExpress.ps1" -ScriptRoot $sr
            if (-not $installScript) {
                Show-WsusPopup -Message "Cannot find Install-WsusWithSqlExpress.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe" -Title "Script Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
                Write-Log "ERROR: Install-WsusWithSqlExpress.ps1 not found"
                return
            }

            $installerPath = if ($controls.InstallPathBox) { $controls.InstallPathBox.Text } else { $script:InstallPath }
            $installerPath = $installerPath.Trim()
            if (-not (Test-SafePath $installerPath)) {
                Show-WsusPopup -Message "Invalid installer path. Please select a valid folder." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $installerResolution = if (Get-Command Resolve-WsusInstallerPath -ErrorAction SilentlyContinue) {
                Resolve-WsusInstallerPath -InstallerPath $installerPath
            } else {
                [pscustomobject]@{ Success = (Test-Path $installerPath); Message = "Installer folder not found: $installerPath" }
            }
            if (-not $installerResolution.Success) {
                Show-WsusPopup -Message $installerResolution.Message -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $installerPath = $installerResolution.InstallerPath
            $script:InstallPath = $installerPath

            $saPassword = if ($controls.InstallSaPassword) { $controls.InstallSaPassword.Password } else { "" }
            $saPasswordConfirm = if ($controls.InstallSaPasswordConfirm) { $controls.InstallSaPasswordConfirm.Password } else { "" }
            if ([string]::IsNullOrWhiteSpace($saPassword) -or [string]::IsNullOrWhiteSpace($saPasswordConfirm)) {
                Show-WsusPopup -Message "SA password and confirmation are required." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            if ($saPassword -ne $saPasswordConfirm) {
                Show-WsusPopup -Message "SA passwords do not match." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }

            $secureSaPassword = ConvertTo-WsusSecureString -Value $saPassword
            $operationPlan = New-WsusInstallOperationPlan -InstallScriptPath $installScript -InstallerPath $installerPath -SaUsername $script:SaUser -SaPassword $secureSaPassword
            $Title = $operationPlan.Title
            $operationPlan.Command
        }
        "restore" {
            $opts = Show-RestoreDialog
            if ($opts.Cancelled) { return }
            if (-not (Test-SafePath $opts.BackupPath)) {
                Show-WsusPopup -Message "Invalid backup path." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $backupResolution = if (Get-Command Resolve-WsusRestoreBackup -ErrorAction SilentlyContinue) {
                Resolve-WsusRestoreBackup -BackupPath $opts.BackupPath -ContentPath $script:ContentPath
            } else {
                [pscustomobject]@{ Success = (Test-Path $opts.BackupPath); BackupFile = $opts.BackupPath; Message = "Backup file not found: $($opts.BackupPath)" }
            }
            if (-not $backupResolution.Success) {
                Show-WsusPopup -Message $backupResolution.Message -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $operationPlan = New-WsusManagementOperationPlan -Id restore -ManagementScriptPath $mgmt -ContentPath $script:ContentPath -SqlInstance $script:SqlInstance -BackupPath $backupResolution.BackupFile
            $Title = $operationPlan.Title
            $operationPlan.Command
        }
        "transfer" {
            $opts = Show-TransferDialog
            if ($opts.Cancelled) { return }
            if (-not (Test-SafePath $opts.SourcePath) -or -not (Test-SafePath $opts.DestinationPath)) {
                Show-WsusPopup -Message "Invalid transfer path." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $exportModule = Join-Path $script:ModulesDir 'WsusExport.psm1'
            $operationPlan = New-WsusTransferOperationPlan -SourcePath $opts.SourcePath -DestinationPath $opts.DestinationPath -ExportModulePath $exportModule -Mode Embedded
            $Title = $operationPlan.Title
            $script:ForceEmbeddedMode = $true
            $operationPlan.Command
        }
        "maintenance" {
            $opts = Show-MaintenanceDialog
            if ($opts.Cancelled) { return }
            $operationPlan = New-WsusMaintenanceOperationPlan -MaintenanceScriptPath $maint -Profile $opts.Profile -ExportPath $opts.ExportPath -SelectedProducts $opts.SelectedProducts
            $Title = $operationPlan.Title
            $operationPlan.Command
        }
        "schedule" {
            $opts = Show-ScheduleTaskDialog
            if ($opts.Cancelled) { return }
            $secureTaskPassword = ConvertTo-WsusSecureString -Value $opts.Password
            $operationPlan = New-WsusScheduleOperationPlan -TaskModulePath $taskModule -Schedule $opts.Schedule -Time $opts.Time -Profile $opts.Profile -RunAsUser $opts.RunAsUser -Password $secureTaskPassword -DayOfWeek $opts.DayOfWeek -DayOfMonth $opts.DayOfMonth
            $Title = $operationPlan.Title
            $operationPlan.Command
        }
        "cleanup" {
            $operationPlan = New-WsusManagementOperationPlan -Id cleanup -ManagementScriptPath $mgmt -SqlInstance $script:SqlInstance
            $Title = $operationPlan.Title
            $operationPlan.Command
        }
        "diagnostics" {
            $operationPlan = New-WsusManagementOperationPlan -Id diagnostics -ManagementScriptPath $mgmt -ContentPath $script:ContentPath -SqlInstance $script:SqlInstance
            $operationPlan.Environment['WSUS_REPORT_PATH'] = Join-Path ([System.IO.Path]::GetTempPath()) ("wsus-diagnostic-report-{0}.json" -f ([guid]::NewGuid().ToString('N')))
            $Title = $operationPlan.Title
            $operationPlan.Command
        }
        "reset" {
            $operationPlan = New-WsusManagementOperationPlan -Id reset -ManagementScriptPath $mgmt
            $Title = $operationPlan.Title
            $operationPlan.Command
        }
        default { "Write-Host 'Unknown: $Id'" }
    }

    $useTerminal = $script:LiveTerminalMode -and -not $script:ForceEmbeddedMode
    $script:ForceEmbeddedMode = $false
    $mode = if ($useTerminal) { 'Terminal' } elseif ($operationPlan -and $operationPlan.Mode) { $operationPlan.Mode } else { 'Embedded' }
    $startedAt = Get-Date

    if ($mode -eq 'Terminal') {
        $controls.LogOutput.Text = "Live Terminal Mode - $Title`r`n`r`nA PowerShell console window has been opened.`r`nYou can interact with the terminal, scroll, and see live output."
    } else {
        $controls.LogOutput.Clear()
        Write-LogOutput "Starting $Title..." -Level Info
    }

    $runnerContext = @{
        Window = $script:window
        Controls = $script:controls
        OperationButtons = $script:OperationButtons
        OperationInputs = $script:OperationInputs
        LogOutput = $controls.LogOutput
        StatusLabel = $controls.StatusLabel
        CancelButton = $controls.BtnCancelOp
        ScriptRoot = $sr
        SetOperationRunning = { param([bool]$running) $script:OperationRunning = $running }
        UpdateButtonState = { Update-WsusButtonState }
    }

    $operationTimeout = if ($operationPlan) { $operationPlan.TimeoutMinutes } else {
        switch ($Id) {
            'cleanup' { Get-WsusOperationTimeout -OperationType Cleanup }
            'maintenance' { Get-WsusOperationTimeout -OperationType Sync }
            'install' { Get-WsusOperationTimeout -OperationType Install }
            'transfer' { Get-WsusOperationTimeout -OperationType Export }
            'diagnostics' { Get-WsusOperationTimeout -OperationType Diagnostics }
            'restore' { Get-WsusOperationTimeout -OperationType Import }
            'reset' { 180 }
            default { Get-WsusOperationTimeout -OperationType Default }
        }
    }

    $reportPath = if ($operationPlan -and $operationPlan.Environment.ContainsKey('WSUS_REPORT_PATH')) { $operationPlan.Environment['WSUS_REPORT_PATH'] } else { $null }
    $cleanupKeys = if ($operationPlan -and $operationPlan.CleanupKeys) { @($operationPlan.CleanupKeys) } else { @() }
    $onComplete = {
        param([bool]$Success)
        $completion = New-WsusGuiOperationCompletion -Title $Title -Success $Success -StartedAt $startedAt -ReportPath $reportPath -CleanupKeys $cleanupKeys
        $logAction = { param([string]$Message, [string]$Level) Write-LogOutput $Message -Level $Level }
        $notificationAction = if ($script:HasNotificationModule) {
            { param([string]$NotificationTitle, [string]$NotificationMessage, [string]$Result) Show-WsusNotification -Title $NotificationTitle -Message $NotificationMessage -Result $Result -EnableBeep:$script:NotificationBeep }.GetNewClosure()
        } else { $null }
        $historyAction = if ($script:HistoryEnabled -and (Get-Command Write-WsusOperationHistory -ErrorAction SilentlyContinue)) {
            { param([string]$OperationType, [TimeSpan]$Duration, [string]$Result, [string]$Summary) Write-WsusOperationHistory -OperationType $OperationType -Duration $Duration -Result $Result -Summary $Summary }.GetNewClosure()
        } else { $null }
        $cleanupAction = { param([string[]]$Keys) Clear-WsusSecretEnvironment -Keys $Keys }.GetNewClosure()

        Invoke-WsusGuiOperationCompletion -Completion $completion -LogAction $logAction -NotificationAction $notificationAction -HistoryAction $historyAction -CleanupAction $cleanupAction -NotificationsEnabled:($script:NotificationsEnabled -and $script:HasNotificationModule) -HistoryEnabled:($script:HistoryEnabled -and $null -ne $historyAction)

        # Install op: WSUS services and content were just provisioned. Refresh the
        # dashboard so the cards flip from "Not Installed" to "Running" without
        # requiring the user to navigate away and back, or wait for the 30 s
        # auto-refresh tick.
        if ($Success -and $Id -eq 'install') {
            try {
                # Update-Dashboard reads WsusService.Test-WsusInstalled etc.;
                # re-evaluation is required because service state was false before.
                Update-WsusButtonState
                Update-Dashboard
            } catch {
                Write-LogOutput "Dashboard refresh after install failed: $($_.Exception.Message)" -Level Warning
            }
        }
        return

        $duration = (Get-Date) - $startedAt
        $resultText = if ($Success) { 'Pass' } else { 'Fail' }
        if ($reportPath -and (Test-Path $reportPath)) {
            Write-LogOutput "Diagnostic report saved to: $reportPath" -Level Info
        }
        if ($script:NotificationsEnabled -and $script:HasNotificationModule) {
            Show-WsusNotification -Title "WSUS Manager - $Title Complete" -Message "$resultText in $([int]$duration.TotalMinutes)m $($duration.Seconds)s" -Result $resultText -EnableBeep:$script:NotificationBeep
        }
        if ($script:HistoryEnabled -and (Get-Command Write-WsusOperationHistory -ErrorAction SilentlyContinue)) {
            Write-WsusOperationHistory -OperationType $Title -Duration $duration -Result $resultText -Summary "Completed via GUI operation runner"
        }
        if (@($cleanupKeys).Count -gt 0 -and (Get-Command Clear-WsusSecretEnvironment -ErrorAction SilentlyContinue)) {
            Clear-WsusSecretEnvironment -Keys $cleanupKeys
        }
    }.GetNewClosure()

    try {
        $script:CurrentProcess = Start-WsusOperation -Command $cmd -Title $Title -Context $runnerContext -Mode $mode -TimeoutMinutes $operationTimeout -Environment $(if ($operationPlan) { $operationPlan.Environment } else { @{} }) -OnComplete $onComplete
    } catch {
        Write-LogOutput "Failed to start operation: $($_.Exception.Message)" -Level Error
        $script:OperationRunning = $false
        Enable-OperationButtons
        Set-Status "Error"
        $controls.BtnCancelOp.Visibility = "Collapsed"
        if (@($cleanupKeys).Count -gt 0 -and (Get-Command Clear-WsusSecretEnvironment -ErrorAction SilentlyContinue)) {
            Clear-WsusSecretEnvironment -Keys $cleanupKeys
        }
        return
    }
}


#region Event Handlers
$controls.BtnDashboard.Add_Click({ Show-Panel "Dashboard" "Dashboard" "BtnDashboard" })
$controls.BtnInstall.Add_Click({
    $controls.InstallPathBox.Text = $script:InstallPath
    if ($controls.InstallSaPassword) { $controls.InstallSaPassword.Password = "" }
    if ($controls.InstallSaPasswordConfirm) { $controls.InstallSaPasswordConfirm.Password = "" }
    Show-Panel "Install" "Install WSUS" "BtnInstall"
})

$controls.InstallSaPassword.Add_PasswordChanged({
    $pwd = $controls.InstallSaPassword.Password
    $strength = Test-PasswordStrength $pwd
    $controls.PasswordStrength.Value = $strength
    $controls.PasswordStrength.Visibility = "Visible"

    if ($strength -lt 100) {
        $controls.PasswordError.Text = "Password must be 15+ chars with number and special character"
        $controls.PasswordError.Visibility = "Visible"
        $controls.BtnRunInstall.IsEnabled = $false
    } else {
        $controls.PasswordError.Visibility = "Collapsed"
        $pwdConfirm = $controls.InstallSaPasswordConfirm.Password
        $controls.BtnRunInstall.IsEnabled = ($pwd -eq $pwdConfirm -and $pwd.Length -gt 0)
    }
})

$controls.InstallSaPasswordConfirm.Add_PasswordChanged({
    $pwd = $controls.InstallSaPassword.Password
    $pwdConfirm = $controls.InstallSaPasswordConfirm.Password
    $strength = Test-PasswordStrength $pwd
    $controls.BtnRunInstall.IsEnabled = ($pwd -eq $pwdConfirm -and $strength -eq 100)
})

$controls.BtnRestore.Add_Click({ Invoke-LogOperation "restore" "Restore Database" })
$controls.BtnCreateGpo.Add_Click({
    $sr = $script:ScriptRoot
    $sourceDir = $null
    $locations = @(
        (Join-Path $sr "DomainController"),
        (Join-Path $sr "Scripts\DomainController"),
        (Join-Path (Split-Path $sr -Parent) "DomainController")
    )
    foreach ($loc in $locations) {
        if (Test-Path $loc) { $sourceDir = $loc; break }
    }

    if (-not $sourceDir) {
        Show-WsusPopup -Message "DomainController folder not found.`n`nExpected locations:`n- $sr\DomainController`n- $sr\Scripts\DomainController" -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    $destDir = "C:\WSUS\WSUS GPO"
    $result = Show-WsusPopup -Message "This will copy GPO files to:`n$destDir`n`nContinue?" -Title "Create GPO Files" -Button ([System.Windows.MessageBoxButton]::YesNo) -Icon ([System.Windows.MessageBoxImage]::Question)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Disable-OperationButtons
    Expand-LogPanel
    Write-LogOutput "=== Creating GPO Files ===" -Level Info

    try {
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            Write-LogOutput "Created folder: $destDir" -Level Success
        }

        Write-LogOutput "Copying from: $sourceDir" -Level Info
        Copy-Item -Path "$sourceDir\*" -Destination $destDir -Recurse -Force
        Write-LogOutput "Files copied successfully" -Level Success

        $gpoCount = (Get-ChildItem "$destDir\WSUS GPOs" -Directory -ErrorAction SilentlyContinue).Count
        $scriptFile = Test-Path "$destDir\Set-WsusGroupPolicy.ps1"

        Write-LogOutput "GPO backups found: $gpoCount" -Level Info
        Write-LogOutput "Import script: $(if($scriptFile){'Present'}else{'Missing'})" -Level $(if($scriptFile){'Success'}else{'Warning'})

        $instructions = @"
GPO files copied to: $destDir

=== AIR-GAP DEPLOYMENT ONLY ===

These GPOs direct ALL Windows Update traffic to the internal
WSUS server. Do NOT deploy on internet-connected systems.

=== NEXT STEPS ===

1. Copy 'C:\WSUS\WSUS GPO' folder to the Domain Controller

2. On the DC, run as Administrator:
   cd 'C:\WSUS\WSUS GPO'
   .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://YOURSERVER:8530"

3. To force clients to update immediately:
   gpupdate /force

   The script automatically pushes to all domain computers
   via schtasks (no WinRM required). Unreachable machines
   will pick up GPOs within 90 min or on next reboot.

4. Verify on clients:
   gpresult /r | findstr WSUS
"@
        Write-LogOutput "" -Level Info
        Write-LogOutput "=== INSTRUCTIONS ===" -Level Info
        Write-LogOutput $instructions -Level Info

        Set-Status "GPO files created"
        Show-WsusPopup -Message "GPO files created at:`n$destDir`n`nWARNING: For air-gapped systems only.`n`nNext steps:`n1. Copy folder to Domain Controller`n2. Run Set-WsusGroupPolicy.ps1 as Admin`n3. Run 'gpupdate /force' on clients`n`nSee log panel for full commands." -Title "GPO Files Created (Air-Gap Only)" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Information) | Out-Null
    } catch {
        Write-LogOutput "Error: $_" -Level Error
        Show-WsusPopup -Message "Failed to create GPO files: $_" -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
    } finally {
        Enable-OperationButtons
    }
})

$controls.BtnTransfer.Add_Click({ Invoke-LogOperation "transfer" "Transfer" })
$controls.BtnMaintenance.Add_Click({ Invoke-LogOperation "maintenance" "Online Sync" })
$controls.BtnSchedule.Add_Click({ Invoke-LogOperation "schedule" "Schedule Task" })
$controls.BtnCleanup.Add_Click({
    $confirm = Show-WsusPopup -Message "Are you sure you want to run deep cleanup?`n`nThis will remove superseded updates, optimize indexes, and shrink the database. This may take 30+ minutes." -Title "Confirm Deep Cleanup" -Button ([System.Windows.MessageBoxButton]::YesNo) -Icon ([System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Invoke-LogOperation "cleanup" "Deep Cleanup"
})
$controls.BtnDiagnostics.Add_Click({ Invoke-LogOperation "diagnostics" "Deep Diagnostics" })
$controls.BtnReset.Add_Click({
    $confirm = Show-WsusPopup -Message "Are you sure you want to reset content verification?`n`nThis will re-verify all downloaded updates and may take several hours." -Title "Confirm Reset Content" -Button ([System.Windows.MessageBoxButton]::YesNo) -Icon ([System.Windows.MessageBoxImage]::Warning)
    if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Invoke-LogOperation "reset" "Reset Content"
})
$controls.BtnAbout.Add_Click({ Show-Panel "About" "About" "BtnAbout" })
$controls.BtnHelp.Add_Click({ Show-Help "Overview" })
$controls.BtnSettings.Add_Click({ Show-SettingsDialog })
if ($controls.BtnHistory) {
    $controls.BtnHistory.Add_Click({
        Show-Panel "History" "History" "BtnHistory"
        Update-HistoryView
    })
}
if ($controls.BtnRefreshHistory) {
    $controls.BtnRefreshHistory.Add_Click({ Update-HistoryView })
}
if ($controls.HistoryFilter) {
    $controls.HistoryFilter.Add_TextChanged({ Update-HistoryView })
}
if ($controls.BtnClearHistory) {
    $controls.BtnClearHistory.Add_Click({
        if (Get-Command Clear-WsusOperationHistory -ErrorAction SilentlyContinue) {
            Clear-WsusOperationHistory | Out-Null
            Update-HistoryView
        }
    })
}

# Online/Offline status indicator -- click to toggle manual override
if ($controls.InternetStatusBorder) {
    $controls.InternetStatusBorder.Add_MouseLeftButtonUp({
        if ($script:ServerModeOverride) {
            # Already manually overridden -- toggle to opposite mode
            $script:ServerModeOverride = if ($script:ServerModeOverride -eq "Online") { "Air-Gap" } else { "Online" }
        } else {
            # Currently auto -- force override to opposite of current auto mode
            $script:ServerModeOverride = if ($script:ServerMode -eq "Online") { "Air-Gap" } else { "Online" }
        }
        $window.Dispatcher.Invoke([Action]{ Update-ServerMode })
    })
    $controls.InternetStatusBorder.Add_MouseRightButtonUp({
        # Right-click clears manual override and returns to auto-detect
        $script:ServerModeOverride = $null
        $window.Dispatcher.Invoke([Action]{ Update-ServerMode })
    })
}

$controls.BtnBrowseInstallPath.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select folder containing SQL Server installers (SQLEXPRADV_x64_ENU.exe, SSMS-Setup-ENU.exe)"
    $fbd.SelectedPath = $script:InstallPath
    try {
        if ($fbd.ShowDialog() -eq "OK") {
            $p = $fbd.SelectedPath
            if (-not (Test-SafePath $p)) {
                Show-WsusPopup -Message "Invalid path." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $controls.InstallPathBox.Text = $p
            $script:InstallPath = $p
        }
    } finally { $fbd.Dispose() }
})

$controls.BtnRunInstall.Add_Click({ Invoke-LogOperation "install" "Install WSUS" })

# Fix SQL Login - add current user as sysadmin to SQL Express
$controls.BtnFixSqlLogin.Add_Click({
    if ($script:OperationRunning) {
        Show-WsusPopup -Message "An operation is already running." -Title "Busy" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) -SuppressDuplicateSeconds 3 | Out-Null
        return
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentUser = $identity.Name
    $sqlInstance = $script:SqlInstance

    Write-LogOutput "[Fix SQL Login] Adding sysadmin for: $currentUser"
    Write-LogOutput "[Fix SQL Login] Target: $sqlInstance"

    $sqlcmd = Get-SqlCmdPath

    if (-not $sqlcmd) {
        Write-LogOutput "[Fix SQL Login] ERROR: sqlcmd.exe not found. Is SQL Server installed?" -Level Error
        Show-WsusPopup -Message "sqlcmd.exe not found. SQL Server does not appear to be installed.`n`nRun 'Install WSUS' first." -Title "SQL Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    try {
        if (-not (Get-Command Add-WsusSqlLogin -ErrorAction SilentlyContinue)) {
            Write-LogOutput "[Fix SQL Login] ERROR: Add-WsusSqlLogin not available" -Level Error
            Show-WsusPopup -Message "Database module not available. Cannot add SQL login." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
            return
        }

        $alreadySysAdmin = $false
        if (Get-Command Test-WsusSqlLoginIsSysAdmin -ErrorAction SilentlyContinue) {
            $alreadySysAdmin = Test-WsusSqlLoginIsSysAdmin -SqlInstance $sqlInstance -LoginName $currentUser
        } elseif (Get-Command Test-WsusSqlLogin -ErrorAction SilentlyContinue) {
            # Fallback: if sysadmin check not available, test at least checks login existence
            $alreadySysAdmin = Test-WsusSqlLogin -SqlInstance $sqlInstance -LoginName $currentUser
        }


        if ($alreadySysAdmin) {
            Write-LogOutput "[Fix SQL Login] $currentUser is already a sysadmin on $sqlInstance" -Level Info
            Show-WsusPopup -Message "$currentUser is already a sysadmin on $sqlInstance.`n`nNo changes needed." -Title "SQL Login Already Configured" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Information) | Out-Null
            return
        }

        $verified = Add-WsusSqlLogin -SqlInstance $sqlInstance -LoginName $currentUser
        if ($verified) {
            Write-LogOutput "[Fix SQL Login] SUCCESS: $currentUser added as sysadmin on $sqlInstance" -Level Success
            Show-WsusPopup -Message "$currentUser has been added as sysadmin on $sqlInstance.`n`nYou can now connect to SQL Server." -Title "SQL Login Fixed" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Information) | Out-Null
        } else {
            Write-LogOutput "[Fix SQL Login] WARNING: Post-add verification did not confirm sysadmin membership" -Level Warning
            Show-WsusPopup -Message "SQL login command completed but post-add verification did not confirm sysadmin membership.`n`nTry running SSMS and connecting manually to confirm." -Title "Check Results" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
    } catch {
        Write-LogOutput "[Fix SQL Login] ERROR: $($_.Exception.Message)" -Level Error
        Show-WsusPopup -Message "Failed to add SQL login: $($_.Exception.Message)`n`nMake sure SQL Express is running and you are a local administrator." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
    }
})

# Cancel operation button - uses centralized cleanup
$controls.BtnCancelOp.Add_Click({
    Write-LogOutput "Cancelling operation..." -Level Warning
    # Call centralized cleanup (handles process kill, event unregister, timer stop, dispose)
    Stop-CurrentOperation
    Enable-OperationButtons
    $controls.BtnCancelOp.Visibility = "Collapsed"
    Set-Status "Cancelled"
    Write-LogOutput "Operation cancelled by user" -Level Warning
})

$controls.HelpBtnOverview.Add_Click({ Show-Help "Overview" })
$controls.HelpBtnDashboard.Add_Click({ Show-Help "Dashboard" })
$controls.HelpBtnOperations.Add_Click({ Show-Help "Operations" })
$controls.HelpBtnAirGap.Add_Click({ Show-Help "AirGap" })
$controls.HelpBtnTroubleshooting.Add_Click({ Show-Help "Troubleshooting" })

$controls.QBtnDiagnostics.Add_Click({ Invoke-LogOperation "diagnostics" "Deep Diagnostics" })
$controls.QBtnCleanup.Add_Click({ Invoke-LogOperation "cleanup" "Deep Cleanup" })
$controls.QBtnMaint.Add_Click({ Invoke-LogOperation "maintenance" "Online Sync" })
$controls.QBtnStart.Add_Click({
    $controls.QBtnStart.IsEnabled = $false
    $controls.QBtnStart.Content = "Starting..."
    $controls.QBtnStart.Background = $script:BrushOrange
    Set-Status "Starting services..."

    Expand-LogPanel

    Write-LogOutput "Starting WSUS services..." -Level Info
    if (Get-Command Start-AllWsusServices -ErrorAction SilentlyContinue) {
        $results = Start-AllWsusServices
        foreach ($key in $results.Keys) {
            if ($results[$key]) { Write-LogOutput "$key started" -Level Success }
            else { Write-LogOutput "Failed to start $key" -Level Warning }
        }
    } else {
        @(
            @{Name="MSSQL`$SQLEXPRESS"; Display="SQL Server Express"},
            @{Name="W3SVC"; Display="IIS"},
            @{Name="WSUSService"; Display="WSUS Service"}
        ) | ForEach-Object {
            try {
                Start-Service -Name $_.Name -ErrorAction Stop
                Write-LogOutput "$($_.Display) started" -Level Success
            } catch {
                Write-LogOutput "Failed to start $($_.Display): $_" -Level Warning
            }
        }
    }
    Start-Sleep -Seconds 2
    Invoke-DashboardRefreshSafe -Source "Start Services"
    Write-LogOutput "Service startup complete" -Level Success
    Set-Status "Ready"
    $controls.QBtnStart.Content = "Start Services"
    $controls.QBtnStart.Background = $script:BrushGreen
    $controls.QBtnStart.IsEnabled = $true
})

$controls.BtnOpenLog.Add_Click({
    if (Test-Path $script:LogDir) { Start-Process explorer.exe -ArgumentList $script:LogDir }
    else { Show-WsusPopup -Message "Log folder not found." -Title "Log" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null }
})

# Log panel buttons
$controls.BtnLiveTerminal.Add_Click({
    $script:LiveTerminalMode = -not $script:LiveTerminalMode
    if ($script:LiveTerminalMode) {
        $controls.BtnLiveTerminal.Content = "Live Terminal: On"
        $controls.BtnLiveTerminal.Background = $script:BrushGreen
        $controls.LogOutput.Text = "Live Terminal Mode enabled.`r`n`r`nOperations will open in a separate PowerShell console window.`r`nYou can interact with the terminal, scroll, and see live output.`r`n`r`nClick 'Live Terminal: On' to switch back to embedded log mode."
    } else {
        $controls.BtnLiveTerminal.Content = "Live Terminal: Off"
        $controls.BtnLiveTerminal.Background = $script:BrushBgCard
        $controls.LogOutput.Clear()
    }
    Save-Settings
})

$controls.BtnToggleLog.Add_Click({
    if ($script:LogExpanded) {
        $controls.LogPanel.Height = (Get-WsusGuiSetting 'LogPanelCollapsed')
        $controls.BtnToggleLog.Content = "Show"
        $script:LogExpanded = $false
    } else {
        Expand-LogPanel
    }
})

$controls.BtnClearLog.Add_Click({ $controls.LogOutput.Clear() })

$controls.BtnSaveLog.Add_Click({ Save-LogToFile })

#region Log Panel Context Menu
$logContextMenu = New-Object System.Windows.Controls.ContextMenu
$menuCopyAll = New-Object System.Windows.Controls.MenuItem
$menuCopyAll.Header = "Copy All"
$menuCopyAll.Add_Click({
    if ($controls.LogOutput.Text.Length -gt 0) {
        [System.Windows.Clipboard]::SetText($controls.LogOutput.Text)
    }
})
$menuSaveToFile = New-Object System.Windows.Controls.MenuItem
$menuSaveToFile.Header = "Save to File..."
$menuSaveToFile.Add_Click({ Save-LogToFile })
$null = $logContextMenu.Items.Add($menuCopyAll)
$null = $logContextMenu.Items.Add($menuSaveToFile)
$controls.LogOutput.ContextMenu = $logContextMenu
#endregion

$controls.BtnBack.Add_Click({ Show-Panel "Dashboard" "Dashboard" "BtnDashboard" })
#endregion

#region Initialize
$script:Splash = Show-SplashScreen
Update-SplashProgress -Splash $script:Splash -Progress 20 -Status "Loading interface..."
$versionDisplay = if ([string]::IsNullOrWhiteSpace($script:AppVersion)) { 'unknown' } else { $script:AppVersion }
$controls.VersionLabel.Text = "v$versionDisplay"
$controls.AboutVersion.Text = "Version $versionDisplay"

# Initialize Live Terminal button state from saved settings
if ($script:LiveTerminalMode) {
    $controls.BtnLiveTerminal.Content = "Live Terminal: On"
    $controls.BtnLiveTerminal.Background = $script:BrushGreen
    $controls.LogOutput.Text = "Live Terminal Mode enabled.`r`n`r`nOperations will open in a separate PowerShell console window.`r`nYou can interact with the terminal, scroll, and see live output.`r`n`r`nClick 'Live Terminal: On' to switch back to embedded log mode."
}

try {
    $iconPath = Resolve-WsusBrandingAssetPath -FileName 'wsus-icon.ico'
    if ($iconPath) {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $iconPath))
    }
} catch { Write-Verbose $_.Exception.Message }

# Load General Atomics logo for sidebar and About page
try {
    $logoPath = Resolve-WsusBrandingAssetPath -FileName 'general_atomics_logo_small.ico'
    if ($logoPath) {
        $logoUri = New-Object System.Uri $logoPath
        $logoBitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $logoBitmap.BeginInit()
        $logoBitmap.UriSource = $logoUri
        $logoBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $logoBitmap.EndInit()
        $controls.SidebarLogo.Source = $logoBitmap
    }
} catch { Write-Verbose $_.Exception.Message }

try {
    $aboutLogoPath = Resolve-WsusBrandingAssetPath -FileName 'general_atomics_logo_big.ico'
    if (-not $aboutLogoPath) {
        $aboutLogoPath = Resolve-WsusBrandingAssetPath -FileName 'general_atomics_logo_small.ico'
    }
    if ($aboutLogoPath) {
        $aboutUri = New-Object System.Uri $aboutLogoPath
        $aboutBitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $aboutBitmap.BeginInit()
        $aboutBitmap.UriSource = $aboutUri
        $aboutBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $aboutBitmap.EndInit()
        $controls.AboutLogo.Source = $aboutBitmap
    }
} catch { Write-Verbose $_.Exception.Message }

Update-SplashProgress -Splash $script:Splash -Progress 60 -Status "Checking services..."
Invoke-DashboardRefreshSafe -Source "Startup"
Update-SplashProgress -Splash $script:Splash -Progress 90 -Status "Starting..."

# Show message if WSUS is not installed
if (-not $script:WsusInstalled) {
    $controls.LogOutput.Text = "WSUS is not installed on this server.`r`n`r`nMost operations are disabled until WSUS is installed.`r`nUse 'Install WSUS' from the Setup menu to begin installation.`r`n"
    Expand-LogPanel
}

# M3: Warn if settings were corrupt and reset to defaults
if ($script:SettingsCorrupt) {
    Show-WsusPopup -Message "Settings file was corrupt and has been reset to defaults.`n`nYour previous configuration was not loaded. Check Settings to reconfigure." -Title "Settings Reset" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
    $script:SettingsCorrupt = $false
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds((Get-WsusTimerInterval -Timer DashboardRefresh))
$timer.Add_Tick({
    if ($controls.DashboardPanel.Visibility -eq "Visible") {
        Invoke-DashboardRefreshSafe -Source "Auto Refresh"
    }
})
$timer.Start()

# Initialize system tray icon
$script:TrayIcon = $null
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Text = "WSUS Manager v$script:AppVersion"
    $ni.Visible = $false
    $iconPath = Resolve-WsusBrandingAssetPath -FileName 'wsus-icon.ico'
    if ($iconPath) {
        $ni.Icon = New-Object System.Drawing.Icon($iconPath)
    } else {
        $ni.Icon = [System.Drawing.SystemIcons]::Application
    }
    # Context menu: Restore + Exit
    $ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $miRestore = $ctxMenu.Items.Add("Restore WSUS Manager")
    $miRestore.add_Click({
        $script:window.Show()
        $script:window.WindowState = "Normal"
        $script:window.Activate()
        $script:TrayIcon.Visible = $false
    })
    $ctxMenu.Items.Add("-") | Out-Null
    $miExit = $ctxMenu.Items.Add("Exit")
    $miExit.add_Click({ $script:window.Close() })
    $ni.ContextMenuStrip = $ctxMenu
    # Double-click restores window
    $ni.add_DoubleClick({
        $script:window.Show()
        $script:window.WindowState = "Normal"
        $script:window.Activate()
        $script:TrayIcon.Visible = $false
    })
    $script:TrayIcon = $ni
} catch {
    Write-Log "System tray icon unavailable: $($_.Exception.Message)"
}

# Intercept minimize → hide to tray when TrayMinimize is enabled
$script:window.Add_StateChanged({
    if ($script:TrayMinimize -and $script:window.WindowState -eq "Minimized" -and $null -ne $script:TrayIcon) {
        $script:window.Hide()
        $script:TrayIcon.Text = "WSUS Manager v$script:AppVersion"
        $script:TrayIcon.Visible = $true
        $script:TrayIcon.ShowBalloonTip(1500, "WSUS Manager", "Running in the system tray. Double-click to restore.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

$script:window.Add_Closing({
    $timer.Stop()
    # Dispose tray icon before closing so it doesn't linger in taskbar
    if ($null -ne $script:TrayIcon) {
        try {
            if ($null -ne $script:TrayIcon.ContextMenuStrip) { $script:TrayIcon.ContextMenuStrip.Dispose() }
            $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose()
        } catch { Write-Verbose $_.Exception.Message }
        $script:TrayIcon = $null
    }
    # Clean up any running operation (suppress log since we're closing)
    try { Stop-CurrentOperation -SuppressLog } catch { Write-Verbose $_.Exception.Message }
})
#endregion

#region Main Entry Point with Error Handling
$script:StartupDuration = ((Get-Date) - $script:StartupTime).TotalMilliseconds
Write-Log (New-WsusGuiLifecycleLogEntry -Event StartupCompleted -StartedAt $script:StartupTime)
Write-Log (New-WsusGuiLifecycleLogEntry -Event RunningForm)

if ($null -ne $script:Splash) {
    Update-SplashProgress -Splash $script:Splash -Progress 100 -Status "Ready"
    Start-Sleep -Milliseconds 300
    try { $script:Splash.Window.Close() } catch { Write-Verbose $_.Exception.Message }
    $script:Splash = $null
}

try {
    if ($script:E2EStartupProbe) {
        $probeCloseTimer = New-Object System.Windows.Threading.DispatcherTimer
        $probeCloseTimer.Interval = [TimeSpan]::FromSeconds($script:E2EStartupProbeSeconds)
        $probeCloseTimer.Add_Tick({
            try {
                $this.Stop()
                if ($script:window -and -not $script:window.Dispatcher.HasShutdownStarted) {
                    $script:window.Close()
                }
            } catch {
                Write-Log "E2E probe close timer error: $($_.Exception.Message)"
            }
        })
        $probeCloseTimer.Start()
    }

    $script:window.ShowDialog() | Out-Null

    if ($script:E2EStartupProbe) {
        $errorPopups = @($script:E2EPopupEvents | Where-Object { $_.icon -eq "Error" })
        if ($errorPopups.Count -gt 0) {
            Write-E2EStartupProbeResult -Status "fail" -Reason "Error popup(s) detected during startup" -FatalError ""
            exit 1
        }

        Write-E2EStartupProbeResult -Status "pass" -Reason "No error popups detected during startup" -FatalError ""
        exit 0
    }
}
catch {
    $errorMsg = "A fatal error occurred:`n`n$($_.Exception.Message)"
    Write-Log "FATAL: $($_.Exception.Message)"
    Write-Log "Stack: $($_.ScriptStackTrace)"

    Show-WsusPopup -Message $errorMsg -Title "WSUS Manager - Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 10 | Out-Null

    if ($script:E2EStartupProbe) {
        Write-E2EStartupProbeResult -Status "fail" -Reason "Unhandled exception during startup" -FatalError $_.Exception.Message
    }

    exit 1
}
finally {
    # Cleanup resources
    try {
        if ($timer) { $timer.Stop() }
        Stop-CurrentOperation -SuppressLog
    }
    catch {
        Write-Verbose $_.Exception.Message
    }
}

Write-Log (New-WsusGuiLifecycleLogEntry -Event ApplicationClosed)
#endregion

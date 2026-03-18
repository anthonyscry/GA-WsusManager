#Requires -Version 5.1
<#
===============================================================================
Script: WsusManagementGui.ps1
Author: Tony Tran, ISSO, Classified Computing, GA-ASI
Version: 4.0.1
===============================================================================
.SYNOPSIS
    WSUS Manager GUI - Modern WPF interface for WSUS management
.DESCRIPTION
    Portable GUI for managing WSUS servers with SQL Express.
    Features: Dashboard, Health checks, Maintenance, Import/Export
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
                    } catch { }
                }
            }
        }
"@ -ErrorAction SilentlyContinue
    [DpiAwareness]::Enable()
} catch {
    # DPI awareness not critical - continue without it
}
#endregion

$script:AppVersion = "4.0.1"
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

$script:LogDir = "C:\WSUS\Logs"
# Use shared daily log file - all operations go to one log
$script:LogPath = Join-Path $script:LogDir "WsusOperations_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:SettingsFile = Join-Path $env:APPDATA "WsusManager\settings.json"
$script:ContentPath = "C:\WSUS"
$script:SqlInstance = ".\SQLEXPRESS"
$script:ExportRoot = "C:\"
$script:InstallPath = "C:\WSUS\SQLDB"
$script:SaUser = "sa"
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
$script:NotificationsEnabled = $true  # Show notifications when operations complete
$script:NotificationBeep = $false     # Beep on completion
# Theme: Dark mode only (light theme not implemented — remove this comment when adding theme support)
$script:TrayMinimize = $false         # Minimize to system tray
$script:HistoryEnabled = $true        # Track operation history

function Write-Log { param([string]$Msg)
    try {
        if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
        "[$(Get-Date -Format 'HH:mm:ss')] $Msg" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch { <# Silently ignore logging failures #> }
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
        [string]$FatalError
    )

    if (-not $script:E2EStartupProbe -or $script:E2EProbeCompleted) { return }

    try {
        $errorPopups = @($script:E2EPopupEvents | Where-Object { $_.Icon -eq "Error" })
        $result = [ordered]@{
            status = $Status
            reason = $Reason
            fatalError = $FatalError
            startupProbeSeconds = $script:E2EStartupProbeSeconds
            resultPath = $script:E2EResultPath
            totalPopupCount = $script:E2EPopupEvents.Count
            errorPopupCount = $errorPopups.Count
            popupEvents = @($script:E2EPopupEvents)
            timestamp = (Get-Date).ToString("o")
        }

        $resultDir = Split-Path -Parent $script:E2EResultPath
        if (-not [string]::IsNullOrWhiteSpace($resultDir) -and -not (Test-Path $resultDir)) {
            New-Item -Path $resultDir -ItemType Directory -Force | Out-Null
        }

        $result | ConvertTo-Json -Depth 6 | Set-Content -Path $script:E2EResultPath -Encoding UTF8
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
        }
    } catch { Write-Log "Failed to load settings: $_" }
}

function Save-Settings {
    try {
        $dir = Split-Path $script:SettingsFile -Parent
        if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        @{ ContentPath=$script:ContentPath; SqlInstance=$script:SqlInstance; ExportRoot=$script:ExportRoot; ServerMode=$script:ServerMode; LiveTerminalMode=$script:LiveTerminalMode; NotificationsEnabled=$script:NotificationsEnabled; NotificationBeep=$script:NotificationBeep; TrayMinimize=$script:TrayMinimize; HistoryEnabled=$script:HistoryEnabled } |
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
    try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}

    foreach ($mod in @("WsusUtilities","WsusConfig","WsusDatabase","WsusServices","WsusFirewall","WsusPermissions","WsusHealth","WsusDialogs","WsusOperationRunner","WsusHistory","WsusNotification","WsusTrending")) {
        $modPath = Join-Path $script:ModulesDir "$mod.psm1"
        if (Test-Path $modPath) {
            try { Import-Module $modPath -Force -DisableNameChecking -ErrorAction Stop }
            catch { Write-Log "Failed to load module ${mod}: $_" }
        }
    }
}

# Re-establish GUI's file-based Write-Log after module imports.
# WsusUtilities.psm1 exports its own Write-Log (stdout-only) which shadows
# the GUI's version defined earlier. The GUI needs file-based logging so
# that log messages persist to C:\WSUS\Logs even when no console is attached.
function Write-Log { param([string]$Msg)
    try {
        if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
        "[$(Get-Date -Format 'HH:mm:ss')] $Msg" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch { <# Silently ignore logging failures #> }
}
#endregion

Write-Log "=== Starting v$script:AppVersion ==="
#endregion

#region Security & Admin Check
function Get-EscapedPath { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    return $Path -replace "'", "''"
}

function Test-SafePath { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -match '[`$;|&<>]') { return $false }
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
        Title="WSUS Manager" Height="736" Width="950" MinHeight="600" MinWidth="800"
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
                            <TextBlock x:Name="VersionLabel" Text="v4.0.1" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                        </StackPanel>
                    </StackPanel>

                </StackPanel>

                <StackPanel DockPanel.Dock="Bottom" Margin="4,0,4,12">
                    <Button x:Name="BtnHistory" Content="☰ History" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnHelp" Content="? Help" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnSettings" Content="⚙ Settings" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnAbout" Content="ℹ About" Style="{StaticResource NavBtn}"/>
                </StackPanel>

                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
                    <StackPanel>
                        <Button x:Name="BtnDashboard" Content="◉ Dashboard" Style="{StaticResource NavBtn}" Background="#21262D" Foreground="{StaticResource Text1}"/>

                        <TextBlock Text="SETUP" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,16,0,4"/>
                        <Button x:Name="BtnInstall" Content="▶ Install WSUS" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnFixSqlLogin" Content="🔑 Fix SQL Login" Style="{StaticResource NavBtn}" ToolTip="Add current user as sysadmin to SQL Express"/>
                        <Button x:Name="BtnRestore" Content="↻ Restore DB" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnCreateGpo" Content="☰ Create GPO" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="TRANSFER" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,16,0,4"/>
                        <Button x:Name="BtnTransfer" Content="⇄ Robocopy" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="MAINTENANCE" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,16,0,4"/>
                        <Button x:Name="BtnMaintenance" Content="↻ Online Sync" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnSchedule" Content="⏱ Schedule Task" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnCleanup" Content="✧ Deep Cleanup" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="DIAGNOSTICS" FontSize="10" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,16,0,4"/>
                        <Button x:Name="BtnDiagnostics" Content="⊘ Run Diagnostics" Style="{StaticResource NavBtn}"/>
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
                            <StackPanel Margin="12,16,12,12">
                                <TextBlock Text="Services" FontSize="10" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card1Value" Text="Loading…" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card1Sub" Text="SQL, WSUS, IIS" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card2Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Green}"/>
                            <StackPanel Margin="12,16,12,12">
                                <TextBlock Text="Database" FontSize="10" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card2Value" Text="Loading…" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card2Sub" Text="SUSDB" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card3Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Orange}"/>
                            <StackPanel Margin="12,16,12,12">
                                <TextBlock Text="Disk" FontSize="10" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card3Value" Text="Loading…" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card3Sub" Text="Free space" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card4Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Blue}"/>
                            <StackPanel Margin="12,16,12,12">
                                <TextBlock Text="Task" FontSize="10" Foreground="{StaticResource Text2}"/>
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
                        <Button x:Name="QBtnDiagnostics" Content="Diagnostics" Style="{StaticResource Btn}" Margin="0,0,8,0"/>
                        <Button x:Name="QBtnCleanup" Content="Deep Cleanup" Style="{StaticResource BtnSec}" Margin="0,0,8,0"/>
                        <Button x:Name="QBtnMaint" Content="Online Sync" Style="{StaticResource BtnSec}" Margin="0,0,8,0"/>
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
                    <ProgressBar x:Name="CleanupProgress" Height="8" Margin="0,8,0,0" Visibility="Collapsed" Foreground="{StaticResource Blue}"/>
                    <ProgressBar x:Name="DiagnosticsProgress" Height="8" Margin="0,8,0,0" Visibility="Collapsed" Foreground="{StaticResource Blue}"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,8,0,0">
                        <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource BtnRed}" Margin="0,0,8,0" Visibility="Collapsed"/>
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
                                 <TextBlock x:Name="AboutVersion" Text="Version 4.0.1" FontSize="12" Foreground="{StaticResource Text2}" Margin="0,4,0,0"/>
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
                            <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="{StaticResource Text2}" LineHeight="20" Text="• Automated WSUS + SQL Express installation&#x0a;• Database backup/restore operations&#x0a;• Air-gapped network export/import&#x0a;• Monthly maintenance automation&#x0a;• Health diagnostics with auto-repair&#x0a;• Deep cleanup and optimization"/>
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
if ($controls.BtnDiagnostics) { $controls.BtnDiagnostics.ToolTip = "Run Diagnostics (Ctrl+D)" }
if ($controls.BtnMaintenance) { $controls.BtnMaintenance.ToolTip = "Online Sync (Ctrl+S)" }
#endregion

#region Helper Functions
$script:LogExpanded = $true
$script:FullLogContent = ""

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
            Close       = { param($s) try { $s.Window.Close() } catch {} }
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
    } catch { }
}

function Write-LogOutput {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')][string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) { 'Success' { "[+]" } 'Warning' { "[!]" } 'Error' { "[-]" } default { "[*]" } }
    $controls.LogOutput.Dispatcher.Invoke([Action]{
        $line = "[$timestamp] $prefix $Message`r`n"
        $script:FullLogContent += $line
        $controls.LogOutput.AppendText($line)
        $controls.LogOutput.ScrollToEnd()
    })
}

function Set-Status {
    param([string]$Text)
    $controls.StatusLabel.Dispatcher.Invoke([Action]{
        $controls.StatusLabel.Text = " - $Text"
    })
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

    if ($SuppressDuplicateSeconds -gt 0) {
        $popupKey = "$Title|$Button|$Icon|$Message"
        $now = Get-Date
        if ($script:PopupHistory.ContainsKey($popupKey)) {
            $elapsed = ($now - $script:PopupHistory[$popupKey]).TotalSeconds
            if ($elapsed -lt $SuppressDuplicateSeconds) {
                Write-Log "Popup suppressed (duplicate within $SuppressDuplicateSeconds s): $Title"
                return [System.Windows.MessageBoxResult]::None
            }
        }
        $script:PopupHistory[$popupKey] = $now
    }

    if ($script:E2EStartupProbe) {
        $script:E2EPopupEvents.Add([PSCustomObject]@{
            timestamp = (Get-Date).ToString("o")
            title = $Title
            button = $Button.ToString()
            icon = $Icon.ToString()
            message = $Message
        }) | Out-Null

        Write-Log "E2E probe captured popup: [$Icon] $Title"

        if ($Button -eq [System.Windows.MessageBoxButton]::YesNo -or $Button -eq [System.Windows.MessageBoxButton]::YesNoCancel) {
            return [System.Windows.MessageBoxResult]::No
        }
        if ($Button -eq [System.Windows.MessageBoxButton]::OKCancel) {
            return [System.Windows.MessageBoxResult]::Cancel
        }
        return [System.Windows.MessageBoxResult]::OK
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
            if ($wfResult -eq [System.Windows.Forms.DialogResult]::OK) { return [System.Windows.MessageBoxResult]::OK }
            if ($wfResult -eq [System.Windows.Forms.DialogResult]::Cancel) { return [System.Windows.MessageBoxResult]::Cancel }
            if ($wfResult -eq [System.Windows.Forms.DialogResult]::Yes) { return [System.Windows.MessageBoxResult]::Yes }
            if ($wfResult -eq [System.Windows.Forms.DialogResult]::No) { return [System.Windows.MessageBoxResult]::No }
            return [System.Windows.MessageBoxResult]::None
        } catch {
            Write-Log "Failed to show popup '$Title': $($_.Exception.Message)"
            return [System.Windows.MessageBoxResult]::None
        }
    }
}

function Get-ServiceStatus {
    $result = @{Running=0; Names=@()}
    foreach ($svc in @("MSSQL`$SQLEXPRESS","WSUSService","W3SVC")) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq "Running") {
                $result.Running++
                $result.Names += switch($svc){"MSSQL`$SQLEXPRESS"{"SQL"}"WSUSService"{"WSUS"}"W3SVC"{"IIS"}}
            }
        } catch { <# Service not found or inaccessible #> }
    }
    return $result
}

function Get-DiskFreeGB {
    try {
        $d = Get-PSDrive -Name "C" -ErrorAction SilentlyContinue
        if ($d.Free) { return [math]::Round($d.Free/1GB,1) }
    } catch { <# Drive access failed #> }
    return 0
}

function Get-DatabaseSizeGB {
    try {
        $sql = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
        if ($sql -and $sql.Status -eq "Running") {
            $q = "SELECT SUM(size * 8 / 1024.0) AS SizeMB FROM sys.master_files WHERE database_id = DB_ID('SUSDB')"
            $r = Invoke-Sqlcmd -ServerInstance $script:SqlInstance -Query $q -ErrorAction SilentlyContinue
            if ($r -and $r.SizeMB) { return [math]::Round($r.SizeMB / 1024, 2) }
        }
    } catch { <# SQL query failed #> }
    return -1
}

function Get-TaskStatus {
    try {
        $t = Get-ScheduledTask -TaskName "WSUS Monthly Maintenance" -ErrorAction SilentlyContinue
        if ($t) { return $t.State.ToString() }
    } catch { <# Task not found #> }
    return "Not Set"
}

function Test-InternetConnection {
    # Use .NET Ping with short timeout (500ms) to avoid blocking UI
    $ping = $null
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send("8.8.8.8", 500)  # Google DNS, 500ms timeout
        return ($null -ne $reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
    } catch {
        return $false
    } finally {
        if ($null -ne $ping) { $ping.Dispose() }
    }
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
}

function Test-PasswordStrength($password) {
    $strength = 0
    if ($password.Length -ge 15) { $strength += 40 }
    if ($password -match '\d') { $strength += 30 }
    if ($password -match '[^a-zA-Z0-9]') { $strength += 30 }
    return $strength
}

function Update-Dashboard {
    Update-ServerMode

    # Check if WSUS is installed first
    $wsusInstalled = Test-WsusInstalled

    # Card 1: Services
    $svc = Get-ServiceStatus
    if ($null -ne $svc -and $controls.Card1Value -and $controls.Card1Sub -and $controls.Card1Bar) {
        if (-not $wsusInstalled) {
            # WSUS not installed
            $controls.Card1Value.Text = "Not Installed"
            $controls.Card1Sub.Text = "Use Install WSUS"
            $controls.Card1Bar.Background = "#F85149"
        } else {
            $running = if ($null -ne $svc.Running) { $svc.Running } else { 0 }
            $names = if ($null -ne $svc.Names) { $svc.Names } else { @() }
            $controls.Card1Value.Text = if ($running -eq 3) { "All Running" } else { "$running/3" }
            $controls.Card1Sub.Text = if ($names.Count -gt 0) { $names -join ", " } else { "Stopped" }
            $controls.Card1Bar.Background = if ($running -eq 3) { "#3FB950" } elseif ($running -gt 0) { "#D29922" } else { "#F85149" }
        }
    }

    # Card 2: Database
    if ($controls.Card2Value -and $controls.Card2Sub -and $controls.Card2Bar) {
        if (-not $wsusInstalled) {
            $controls.Card2Value.Text = "N/A"
            $controls.Card2Sub.Text = "WSUS not installed"
            $controls.Card2Bar.Background = "#30363D"
        } else {
            $db = Get-DatabaseSizeGB
            if ($db -ge 0) {
                $controls.Card2Value.Text = "$db / 10 GB"
                $controls.Card2Sub.Text = if ($db -ge 9) { "Critical!" } elseif ($db -ge 7) { "Warning" } else { "Healthy" }
                $controls.Card2Bar.Background = if ($db -ge 9) { "#F85149" } elseif ($db -ge 7) { "#D29922" } else { "#3FB950" }
            } else {
                $controls.Card2Value.Text = "Offline"
                $controls.Card2Sub.Text = "SQL stopped"
                $controls.Card2Bar.Background = "#D29922"
            }
            # Add trending data snapshot and display trend
            if (Get-Command Add-WsusTrendSnapshot -ErrorAction SilentlyContinue) {
                if ($db -ge 0) { Add-WsusTrendSnapshot -DatabaseSizeGB $db }
                $trend = Get-WsusTrendSummary
                if ($trend -and $trend.Status -eq "OK") {
                    $sign = if ($trend.GrowthPerMonth -ge 0) { "+" } else { "" }
                    $trendTxt = "$db GB  $sign$([math]::Round($trend.GrowthPerMonth,1))/mo"
                    if ($null -ne $controls.Card2Sub) { $controls.Card2Sub.Text = $trendTxt }
                    # Alert if < 90 days until full
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
    }

    # Card 3: Disk
    $disk = Get-DiskFreeGB
    if ($controls.Card3Value -and $controls.Card3Sub -and $controls.Card3Bar) {
        $controls.Card3Value.Text = "$disk GB"
        $controls.Card3Sub.Text = if ($disk -lt 10) { "Critical!" } elseif ($disk -lt 50) { "Low" } else { "OK" }
        $controls.Card3Bar.Background = if ($disk -lt 10) { "#F85149" } elseif ($disk -lt 50) { "#D29922" } else { "#3FB950" }
    }

    # Card 4: Task
    if ($controls.Card4Value -and $controls.Card4Bar) {
        if (-not $wsusInstalled) {
            $controls.Card4Value.Text = "N/A"
            $controls.Card4Bar.Background = "#30363D"
        } else {
            $task = Get-TaskStatus
            $controls.Card4Value.Text = $task
            $controls.Card4Bar.Background = if ($task -eq "Ready") { "#3FB950" } else { "#D29922" }
        }
    }

    # Configuration display
    if ($controls.CfgContentPath) { $controls.CfgContentPath.Text = $script:ContentPath }
    if ($controls.CfgSqlInstance) { $controls.CfgSqlInstance.Text = $script:SqlInstance }
    if ($controls.CfgExportRoot) { $controls.CfgExportRoot.Text = $script:ExportRoot }
    if ($controls.CfgLogPath) { $controls.CfgLogPath.Text = $script:LogDir }
    if ($controls.StatusLabel) { $controls.StatusLabel.Text = "Updated $(Get-Date -Format 'HH:mm:ss')" }

    # Update Health Score
    if ($controls.HealthScoreValue -and (Get-Command Get-WsusHealthScore -ErrorAction SilentlyContinue)) {
        try {
            $health = Get-WsusHealthScore -SqlInstance $script:SqlInstance -ContentPath $script:ContentPath
            if ($health.Score -ge 0) {
                $controls.HealthScoreValue.Text = "$($health.Score)"
                $controls.HealthScoreBar.Value = $health.Score
                $scoreColor = switch($health.Grade) {
                    "Green"   { "#3FB950" }
                    "Yellow"  { "#D29922" }
                    default   { "#F85149" }
                }
                $controls.HealthScoreValue.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($scoreColor)
                $controls.HealthScoreGrade.Text = $health.Grade
                $controls.HealthScoreGrade.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($scoreColor)
                # Update tray tooltip with health grade
                if ($null -ne $script:TrayIcon) {
                    $script:TrayIcon.Text = "WSUS Manager  - Health: $($health.Grade) ($($health.Score)/100)"
                }
            } else {
                $controls.HealthScoreValue.Text = "N/A"
                $controls.HealthScoreGrade.Text = "Unknown"
            }
        } catch { }
    }

    # Last Successful Sync
    if ($controls.LastSyncText) {
        try {
            $wsus = Get-WsusServer -ErrorAction SilentlyContinue
            if ($wsus) {
                $sub = $wsus.GetSubscription()
                $lastSync = $sub.LastSuccessfulSynchronizationTime
                # Fallback: LastSuccessfulSynchronizationTime can return MinValue on air-gapped servers
                # even after a successful sync — check GetLastSynchronizationInfo() instead
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
                    $syncColor = if ($daysAgo -le 7) { "#3FB950" } elseif ($daysAgo -le 30) { "#D29922" } else { "#F85149" }
                    $controls.LastSyncText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($syncColor)
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

    if ($script:RefreshInProgress) { return }

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
• Automated maintenance and cleanup
• Health monitoring with auto-repair
• Database size monitoring (10GB limit)

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
• Health Check - Diagnostics only
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
• Export (Online) - Full or differential export to USB
• Import (Air-Gap) - Import from external media

MAINTENANCE
• Monthly (Online only) - Sync, decline superseded, cleanup, backup
• Schedule Task (Online only) - Create/update the maintenance scheduled task
• Deep Cleanup - Remove obsolete, shrink database

DIAGNOSTICS
• Health Check - Read-only verification
• Repair - Auto-fix common issues
"@

    AirGap = @"
AIR-GAP WORKFLOW

Two-server model for disconnected networks:
• Online WSUS: Internet-connected
• Air-Gap WSUS: Disconnected

WORKFLOW
1. On Online server: Run Maintenance, then Export
2. Transfer USB to air-gap network
3. On Air-Gap server: Import, then Restore DB

EXPORT OPTIONS
• Full: Complete DB + all files (100 GB+)
• Differential: Recent updates only (smaller)

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
4. Run Health + Repair

DATABASE OFFLINE
• Start SQL Server Express service
• Check disk space
• Run Health Check

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
    $result = @{ Cancelled = $true; ExportType = "Full"; DestinationPath = ""; DaysOld = 30 }

    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ExportDialog")
    $dlg.Title = "Export to Media"
    $dlg.Width = 480
    $dlg.Height = 360
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    $dlg.ResizeMode = "NoResize"
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

    $radioDiff = New-Object System.Windows.Controls.RadioButton
    $radioDiff.Content = "Differential"
    $radioDiff.Foreground = $script:BrushText1
    $radioPanel.Children.Add($radioDiff)
    $stack.Children.Add($radioPanel)

    $daysPanel = New-Object System.Windows.Controls.StackPanel
    $daysPanel.Orientation = "Horizontal"
    $daysPanel.Margin = "0,0,0,12"
    $daysPanel.Visibility = "Collapsed"

    $daysLbl = New-Object System.Windows.Controls.TextBlock
    $daysLbl.Text = "Days:"
    $daysLbl.Foreground = $script:BrushText2
    $daysLbl.VerticalAlignment = "Center"
    $daysLbl.Margin = "0,0,8,0"
    $daysPanel.Children.Add($daysLbl)

    $daysTxt = New-Object System.Windows.Controls.TextBox
    $daysTxt.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "ExportDaysTextBox")
    $daysTxt.Text = "30"
    $daysTxt.Width = 50
    $daysTxt.Background = $script:BrushBgCard
    $daysTxt.Foreground = $script:BrushText1
    $daysTxt.Padding = "4"
    $daysPanel.Children.Add($daysTxt)
    $stack.Children.Add($daysPanel)

    $radioDiff.Add_Checked({ $daysPanel.Visibility = "Visible" }.GetNewClosure())
    $radioFull.Add_Checked({ $daysPanel.Visibility = "Collapsed" }.GetNewClosure())

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
    }.GetNewClosure())
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
        $daysVal = 30
        if ($radioDiff.IsChecked -and -not [int]::TryParse($daysTxt.Text, [ref]$daysVal)) {
            Show-WsusPopup -Message "Invalid days value." -Title "Export" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $result.Cancelled = $false
        $result.ExportType = if($radioFull.IsChecked){"Full"}else{"Differential"}
        $result.DestinationPath = $destTxt.Text
        $result.DaysOld = $daysVal
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($exportBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
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
    $dlg.Height = 320
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    $dlg.ResizeMode = "NoResize"
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
    }.GetNewClosure())
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
    }.GetNewClosure())
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
    }.GetNewClosure())
    $btnPanel.Children.Add($importBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-RestoreDialog {
    $result = @{ Cancelled = $true; BackupPath = "" }

    # Find backup files in C:\WSUS
    $backupPath = "C:\WSUS"
    $backupFiles = @()
    if (Test-Path $backupPath) {
        $backupFiles = Get-ChildItem -Path $backupPath -Filter "*.bak" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    }

    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "RestoreDialog")
    $dlg.Title = "Restore Database"
    $dlg.Width = 480
    $dlg.Height = 340
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Restore WSUS Database"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = $script:BrushText1
    $title.Margin = "0,0,0,8"
    $stack.Children.Add($title)

    $restoreWarning = New-Object System.Windows.Controls.TextBlock
    $restoreWarning.Text = "This will permanently replace the current SUSDB database. Create a backup first."
    $restoreWarning.FontSize = 12
    $restoreWarning.Foreground = $script:BrushRed
    $restoreWarning.TextWrapping = "Wrap"
    $restoreWarning.Margin = "0,0,0,12"
    $stack.Children.Add($restoreWarning)

    # Backup file selection
    $fileLbl = New-Object System.Windows.Controls.TextBlock
    $fileLbl.Text = "Backup file:"
    $fileLbl.Foreground = $script:BrushText2
    $fileLbl.Margin = "0,0,0,4"
    $stack.Children.Add($fileLbl)

    $filePanel = New-Object System.Windows.Controls.DockPanel
    $filePanel.Margin = "0,0,0,12"

    $browseBtn = New-Object System.Windows.Controls.Button
    $browseBtn.Content = "Browse"
    $browseBtn.Padding = "10,4"
    $browseBtn.Background = $script:BrushBgCard
    $browseBtn.Foreground = $script:BrushText1
    $browseBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($browseBtn, "Right")
    $filePanel.Children.Add($browseBtn)

    $fileTxt = New-Object System.Windows.Controls.TextBox
    $fileTxt.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "RestoreFileTextBox")
    $fileTxt.Margin = "0,0,8,0"
    $fileTxt.Background = $script:BrushBgCard
    $fileTxt.Foreground = $script:BrushText1
    $fileTxt.Padding = "8,4"
    # Pre-fill with most recent backup if found
    if ($backupFiles.Count -gt 0) {
        $fileTxt.Text = $backupFiles[0].FullName
    }
    $filePanel.Children.Add($fileTxt)

    $browseBtn.Add_Click({
        $ofd = New-Object Microsoft.Win32.OpenFileDialog
        $ofd.Filter = "Backup Files (*.bak)|*.bak|All Files (*.*)|*.*"
        $ofd.InitialDirectory = "C:\WSUS"
        if ($ofd.ShowDialog() -eq $true) { $fileTxt.Text = $ofd.FileName }
    }.GetNewClosure())
    $stack.Children.Add($filePanel)

    # Show recent backups if any found
    if ($backupFiles.Count -gt 0) {
        $recentLbl = New-Object System.Windows.Controls.TextBlock
        $recentLbl.Text = "Recent backups found in C:\WSUS:"
        $recentLbl.Foreground = $script:BrushText2
        $recentLbl.Margin = "0,0,0,6"
        $stack.Children.Add($recentLbl)

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
        }.GetNewClosure())
        $stack.Children.Add($listBox)
    } else {
        $noFilesLbl = New-Object System.Windows.Controls.TextBlock
        $noFilesLbl.Text = "No backup files found in C:\WSUS. Use Browse to select a backup file."
        $noFilesLbl.Foreground = $script:BrushOrange
        $noFilesLbl.TextWrapping = "Wrap"
        $noFilesLbl.Margin = "0,0,0,12"
        $stack.Children.Add($noFilesLbl)
    }

    # Warning message
    $warnLbl = New-Object System.Windows.Controls.TextBlock
    $warnLbl.Text = "Warning: This will replace the current SUSDB database!"
    $warnLbl.Foreground = $script:BrushRed
    $warnLbl.FontWeight = "SemiBold"
    $warnLbl.Margin = "0,0,0,16"
    $stack.Children.Add($warnLbl)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $restoreBtn = New-Object System.Windows.Controls.Button
    $restoreBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "RestoreButton")
    $restoreBtn.Content = "Restore"
    $restoreBtn.Padding = "12,8"
    $restoreBtn.Background = $script:BrushRed
    $restoreBtn.Foreground = $script:BrushText1
    $restoreBtn.BorderThickness = 0
    $restoreBtn.Margin = "0,0,8,0"
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
    }.GetNewClosure())
    $btnPanel.Children.Add($restoreBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-MaintenanceDialog {
    $result = @{ Cancelled = $true; Profile = ""; ExportPath = ""; DifferentialPath = ""; ExportDays = 30 }

    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "MaintenanceDialog")
    $dlg.Title = "Online Sync"
    $dlg.Width = 520
    $dlg.Height = 580
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Select Sync Profile"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = $script:BrushText1
    $title.Margin = "0,0,0,16"
    $stack.Children.Add($title)

    # Radio buttons for sync options
    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full Sync"
    $radioFull.Foreground = $script:BrushText1
    $radioFull.Margin = "0,0,0,4"
    $radioFull.IsChecked = $true
    $stack.Children.Add($radioFull)

    $fullDesc = New-Object System.Windows.Controls.TextBlock
    $fullDesc.Text = "Sync > Cleanup > Ultimate Cleanup > Backup > Export"
    $fullDesc.Foreground = $script:BrushText2
    $fullDesc.FontSize = 12
    $fullDesc.Margin = "20,0,0,12"
    $stack.Children.Add($fullDesc)

    $radioQuick = New-Object System.Windows.Controls.RadioButton
    $radioQuick.Content = "Quick Sync"
    $radioQuick.Foreground = $script:BrushText1
    $radioQuick.Margin = "0,0,0,4"
    $stack.Children.Add($radioQuick)

    $quickDesc = New-Object System.Windows.Controls.TextBlock
    $quickDesc.Text = "Sync > Cleanup > Backup (skip heavy cleanup)"
    $quickDesc.Foreground = $script:BrushText2
    $quickDesc.FontSize = 12
    $quickDesc.Margin = "20,0,0,12"
    $stack.Children.Add($quickDesc)

    $radioSync = New-Object System.Windows.Controls.RadioButton
    $radioSync.Content = "Sync Only"
    $radioSync.Foreground = $script:BrushText1
    $radioSync.Margin = "0,0,0,4"
    $stack.Children.Add($radioSync)

    $syncDesc = New-Object System.Windows.Controls.TextBlock
    $syncDesc.Text = "Synchronize and approve updates only (no export)"
    $syncDesc.Foreground = $script:BrushText2
    $syncDesc.FontSize = 12
    $syncDesc.Margin = "20,0,0,12"
    $stack.Children.Add($syncDesc)

    # Export Settings Section
    $exportTitle = New-Object System.Windows.Controls.TextBlock
    $exportTitle.Text = "Export Settings (optional)"
    $exportTitle.FontSize = 12
    $exportTitle.FontWeight = "SemiBold"
    $exportTitle.Foreground = $script:BrushText1
    $exportTitle.Margin = "0,0,0,12"
    $stack.Children.Add($exportTitle)

    # Full Export Path
    $exportLabel = New-Object System.Windows.Controls.TextBlock
    $exportLabel.Text = "Full Export Path (backup + all content):"
    $exportLabel.Foreground = $script:BrushText2
    $exportLabel.FontSize = 12
    $exportLabel.Margin = "0,0,0,4"
    $stack.Children.Add($exportLabel)

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

    $stack.Children.Add($exportPanel)

    # Differential Export Path
    $diffLabel = New-Object System.Windows.Controls.TextBlock
    $diffLabel.Text = "Differential Export Path (recent changes only):"
    $diffLabel.Foreground = $script:BrushText2
    $diffLabel.FontSize = 12
    $diffLabel.Margin = "0,0,0,4"
    $stack.Children.Add($diffLabel)

    $diffPanel = New-Object System.Windows.Controls.DockPanel
    $diffPanel.Margin = "0,0,0,12"

    $diffBrowse = New-Object System.Windows.Controls.Button
    $diffBrowse.Content = "..."
    $diffBrowse.Width = 30
    $diffBrowse.Background = $script:BrushBgCard
    $diffBrowse.Foreground = $script:BrushText1
    $diffBrowse.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($diffBrowse, "Right")
    $diffPanel.Children.Add($diffBrowse)

    $diffBox = New-Object System.Windows.Controls.TextBox
    $diffBox.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SyncDiffExportTextBox")
    $diffBox.Background = $script:BrushBgCard
    $diffBox.Foreground = $script:BrushText1
    $diffBox.BorderThickness = 0
    $diffBox.Padding = "8,6"
    $diffBox.Margin = "0,0,4,0"
    $diffPanel.Children.Add($diffBox)

    $stack.Children.Add($diffPanel)

    # Export Days
    $daysPanel = New-Object System.Windows.Controls.StackPanel
    $daysPanel.Orientation = "Horizontal"
    $daysPanel.Margin = "0,0,0,20"

    $daysLabel = New-Object System.Windows.Controls.TextBlock
    $daysLabel.Text = "Differential includes files from last"
    $daysLabel.Foreground = $script:BrushText2
    $daysLabel.FontSize = 12
    $daysLabel.VerticalAlignment = "Center"
    $daysPanel.Children.Add($daysLabel)

    $daysBox = New-Object System.Windows.Controls.TextBox
    $daysBox.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SyncDaysTextBox")
    $daysBox.Text = "30"
    $daysBox.Width = 50
    $daysBox.Background = $script:BrushBgCard
    $daysBox.Foreground = $script:BrushText1
    $daysBox.BorderThickness = 0
    $daysBox.Padding = "8,4"
    $daysBox.Margin = "8,0,8,0"
    $daysBox.HorizontalContentAlignment = "Center"
    $daysPanel.Children.Add($daysBox)

    $daysLabel2 = New-Object System.Windows.Controls.TextBlock
    $daysLabel2.Text = "days"
    $daysLabel2.Foreground = $script:BrushText2
    $daysLabel2.FontSize = 12
    $daysLabel2.VerticalAlignment = "Center"
    $daysPanel.Children.Add($daysLabel2)

    $stack.Children.Add($daysPanel)

    # Browse button handlers
    $exportBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select full export destination (network share or local path)"
        try {
            if ($fbd.ShowDialog() -eq "OK") {
                $exportBox.Text = $fbd.SelectedPath
            }
        } finally { $fbd.Dispose() }
    }.GetNewClosure())

    $diffBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select differential export destination (e.g., USB drive)"
        try {
            if ($fbd.ShowDialog() -eq "OK") {
                $diffBox.Text = $fbd.SelectedPath
            }
        } finally { $fbd.Dispose() }
    }.GetNewClosure())

    # Button panel
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
        $result.DifferentialPath = $diffBox.Text.Trim()
        $days = 30
        if ([int]::TryParse($daysBox.Text, [ref]$days)) { $result.ExportDays = $days }
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($runBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
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
        DayOfWeek = "Saturday"
        DayOfMonth = 1
        Time = "02:00"
        Profile = "Full"
        RunAsUser = "DoD_Admin"
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
                <ComboBoxItem Content="Tuesday"/>
                <ComboBoxItem Content="Wednesday"/>
                <ComboBoxItem Content="Thursday"/>
                <ComboBoxItem Content="Friday"/>
                <ComboBoxItem Content="Saturday" IsSelected="True"/>
            </ComboBox>
        </StackPanel>

        <!-- Day of Month (hidden by default) -->
        <StackPanel x:Name="DayOfMonthPanel" Visibility="Collapsed" Margin="0,0,0,12">
            <TextBlock Text="Day of Month (1-31):" Foreground="#8B949E" Margin="0,0,0,4"/>
            <TextBox x:Name="DomBox" Text="1" Style="{StaticResource DarkTextBox}"/>
        </StackPanel>

        <!-- Start Time -->
        <TextBlock Text="Start Time (HH:mm):" Foreground="#8B949E" Margin="0,0,0,4"/>
        <TextBox x:Name="TimeBox" Text="02:00" Style="{StaticResource DarkTextBox}" Margin="0,0,0,12"
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

        <TextBlock Text="Username (e.g., DoD_Admin or DOMAIN\user):" Foreground="#8B949E" Margin="0,0,0,4"/>
        <TextBox x:Name="UserBox" Text="DoD_Admin" Style="{StaticResource DarkTextBox}" Margin="0,0,0,12"
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
    $result = @{ Cancelled = $true; SourcePath = ""; DestinationPath = ""; DaysOld = 0; UseDateFilter = $false }

    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "TransferDialog")
    $dlg.Title = "Transfer Data"
    $dlg.Width = 480
    $dlg.Height = 340
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Transfer WSUS Data"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = $script:BrushText1
    $title.Margin = "0,0,0,16"
    $stack.Children.Add($title)

    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Uses robocopy to copy WSUS content between folders. Non-destructive — only copies files, never deletes."
    $desc.FontSize = 12
    $desc.Foreground = $script:BrushText2
    $desc.TextWrapping = "Wrap"
    $desc.Margin = "0,0,0,16"
    $stack.Children.Add($desc)

    # Source folder
    $srcLbl = New-Object System.Windows.Controls.TextBlock
    $srcLbl.Text = "Source folder:"
    $srcLbl.Foreground = $script:BrushText2
    $srcLbl.Margin = "0,0,0,4"
    $stack.Children.Add($srcLbl)

    $srcPanel = New-Object System.Windows.Controls.DockPanel
    $srcPanel.Margin = "0,0,0,12"

    $srcBtn = New-Object System.Windows.Controls.Button
    $srcBtn.Content = "Browse"
    $srcBtn.Padding = "10,4"
    $srcBtn.Background = $script:BrushBgCard
    $srcBtn.Foreground = $script:BrushText1
    $srcBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($srcBtn, "Right")
    $srcPanel.Children.Add($srcBtn)

    $srcTxt = New-Object System.Windows.Controls.TextBox
    $srcTxt.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "TransferSourceTextBox")
    $srcTxt.Background = $script:BrushBgCard
    $srcTxt.Foreground = $script:BrushText1
    $srcTxt.Padding = "8,4"
    $srcPanel.Children.Add($srcTxt)

    $srcBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select source folder (e.g. C:\WSUS\WsusContent)"
        try { if ($fbd.ShowDialog() -eq "OK") { $srcTxt.Text = $fbd.SelectedPath } }
        finally { $fbd.Dispose() }
    }.GetNewClosure())
    $stack.Children.Add($srcPanel)

    # Destination folder
    $dstLbl = New-Object System.Windows.Controls.TextBlock
    $dstLbl.Text = "Destination folder:"
    $dstLbl.Foreground = $script:BrushText2
    $dstLbl.Margin = "0,0,0,4"
    $stack.Children.Add($dstLbl)

    $dstPanel = New-Object System.Windows.Controls.DockPanel
    $dstPanel.Margin = "0,0,0,12"

    $dstBtn = New-Object System.Windows.Controls.Button
    $dstBtn.Content = "Browse"
    $dstBtn.Padding = "10,4"
    $dstBtn.Background = $script:BrushBgCard
    $dstBtn.Foreground = $script:BrushText1
    $dstBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($dstBtn, "Right")
    $dstPanel.Children.Add($dstBtn)

    $dstTxt = New-Object System.Windows.Controls.TextBox
    $dstTxt.SetValue([System.Windows.Automation.Properties]::AutomationIdProperty, "TransferDestTextBox")
    $dstTxt.Background = $script:BrushBgCard
    $dstTxt.Foreground = $script:BrushText1
    $dstTxt.Padding = "8,4"
    $dstPanel.Children.Add($dstTxt)

    $dstBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select destination folder (e.g. D:\WsusContent)"
        try { if ($fbd.ShowDialog() -eq "OK") { $dstTxt.Text = $fbd.SelectedPath } }
        finally { $fbd.Dispose() }
    }.GetNewClosure())
    $stack.Children.Add($dstPanel)

    # Differential date filter option
    $diffPanel = New-Object System.Windows.Controls.StackPanel
    $diffPanel.Orientation = "Horizontal"
    $diffPanel.Margin = "0,0,0,16"

    $chkDiff = New-Object System.Windows.Controls.CheckBox
    $chkDiff.Content = "Only copy files modified in the last"
    $chkDiff.Foreground = $script:BrushText1
    $chkDiff.VerticalAlignment = "Center"
    $diffPanel.Children.Add($chkDiff)

    $txtDays = New-Object System.Windows.Controls.TextBox
    $txtDays.Text = "30"
    $txtDays.Width = 50
    $txtDays.Background = $script:BrushBgCard
    $txtDays.Foreground = $script:BrushText1
    $txtDays.Padding = "4,2"
    $txtDays.Margin = "4,0,0,0"
    $diffPanel.Children.Add($txtDays)

    $daysLbl = New-Object System.Windows.Controls.TextBlock
    $daysLbl.Text = "days"
    $daysLbl.Foreground = $script:BrushText2
    $daysLbl.VerticalAlignment = "Center"
    $diffPanel.Children.Add($daysLbl)

    $stack.Children.Add($diffPanel)

    # Buttons
    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $runBtn = New-Object System.Windows.Controls.Button
    $runBtn.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "StartTransferButton")
    $runBtn.Content = "Start Transfer"
    $runBtn.Padding = "12,8"
    $runBtn.Background = $script:BrushBlue
    $runBtn.Foreground = $script:BrushText1
    $runBtn.BorderThickness = 0
    $runBtn.Margin = "0,0,8,0"
    $runBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($srcTxt.Text)) {
            Show-WsusPopup -Message "Select a source folder." -Title "Transfer" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        if (-not (Test-Path $srcTxt.Text)) {
            Show-WsusPopup -Message "Source folder not found: $($srcTxt.Text)" -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($dstTxt.Text)) {
            Show-WsusPopup -Message "Select a destination folder." -Title "Transfer" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $result.Cancelled = $false
        $result.SourcePath = $srcTxt.Text
        $result.DestinationPath = $dstTxt.Text
        $result.UseDateFilter = $chkDiff.IsChecked
        if ($chkDiff.IsChecked) {
            $daysVal = 30
            if ([int]::TryParse($txtDays.Text, [ref]$daysVal) -and $daysVal -gt 0) {
                $result.DaysOld = $daysVal
            } else {
                $result.DaysOld = 30
            }
        } else {
            $result.DaysOld = 0
        }
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($runBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-SettingsDialog {
    $dlg = New-Object System.Windows.Window
    $dlg.SetValue([System.Windows.Automation.AutomationProperties]::AutomationIdProperty, "SettingsDialog")
    $dlg.Title = "Settings"
    $dlg.Width = 480
    $dlg.Height = 430
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = $script:BrushBgDark
    $dlg.ResizeMode = "NoResize"

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
    }.GetNewClosure())
    $btnPanel.Children.Add($saveBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "12,8"
    $cancelBtn.Background = $script:BrushBgCard
    $cancelBtn.Foreground = $script:BrushText1
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
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

    # Block if operation is already running
    if ($script:OperationRunning) {
        Show-WsusPopup -Message "An operation is already running. Please wait for it to complete or cancel it." -Title "Operation In Progress" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) -SuppressDuplicateSeconds 3 | Out-Null
        return
    }

    # Preflight: check SQL connectivity for operations that need it
    $dbOperations = @("restore", "cleanup", "diagnostics", "maintenance")
    if ($Id -in $dbOperations) {
        $sqlInstance = $script:SqlInstance
        $sqlcmdPaths = @(
            "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
            "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
            "C:\Program Files\Microsoft SQL Server\170\Tools\Binn\sqlcmd.exe",
            "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\sqlcmd.exe",
            "C:\Program Files\Microsoft SQL Server\150\Tools\Binn\sqlcmd.exe"
        )
        $sqlcmd = $sqlcmdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $sqlcmd) {
            Show-WsusPopup -Message "sqlcmd.exe not found. SQL Server does not appear to be installed.`n`nRun 'Install WSUS' first, or use 'Fix SQL Login' to troubleshoot." -Title "SQL Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
            Write-Log "PREFLIGHT FAIL: sqlcmd.exe not found for operation '$Id'"
            return
        }

        try {
            # Test SQL connectivity using exit code (reliable) instead of parsing output
            # Redirect stderr to a temp file so we can show the actual error
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

    # Guard Online-only operations
    if ($script:ServerMode -eq "Air-Gap" -and $Id -in @("maintenance", "schedule")) {
        Show-WsusPopup -Message "This operation is only available on the Online WSUS server." -Title "Online Only" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) -SuppressDuplicateSeconds 3 | Out-Null
        return
    }

    Write-Log "Run-LogOp: $Id"

    $sr = $script:ScriptRoot

    # Find management script - check multiple locations
    $mgmt = $null
    $mgmtLocations = @(
        (Join-Path $sr "Invoke-WsusManagement.ps1"),
        (Join-Path $sr "Scripts\Invoke-WsusManagement.ps1")
    )
    foreach ($loc in $mgmtLocations) {
        if (Test-Path $loc) { $mgmt = $loc; break }
    }

    # Find maintenance script - check multiple locations
    $maint = $null
    $maintLocations = @(
        (Join-Path $sr "Invoke-WsusMonthlyMaintenance.ps1"),
        (Join-Path $sr "Scripts\Invoke-WsusMonthlyMaintenance.ps1")
    )
    foreach ($loc in $maintLocations) {
        if (Test-Path $loc) { $maint = $loc; break }
    }

    # Find scheduled task module - check multiple locations
    $taskModule = $null
    $taskModuleLocations = @(
        (Join-Path $sr "Modules\WsusScheduledTask.psm1"),
        (Join-Path (Split-Path $sr -Parent) "Modules\WsusScheduledTask.psm1")
    )
    foreach ($loc in $taskModuleLocations) {
        if (Test-Path $loc) { $taskModule = $loc; break }
    }

    # Validate scripts exist before proceeding
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

    $cp = Get-EscapedPath $script:ContentPath
    $sql = Get-EscapedPath $script:SqlInstance
    $mgmtSafe = if ($mgmt) { Get-EscapedPath $mgmt } else { $null }
    $maintSafe = if ($maint) { Get-EscapedPath $maint } else { $null }
    $taskModuleSafe = if ($taskModule) { Get-EscapedPath $taskModule } else { $null }

    # Handle dialog-based operations
    $cmd = switch ($Id) {
        "install" {
            # Find install script - check same locations as other scripts
            $installScript = $null
            $installLocations = @(
                (Join-Path $sr "Install-WsusWithSqlExpress.ps1"),
                (Join-Path $sr "Scripts\Install-WsusWithSqlExpress.ps1")
            )
            foreach ($loc in $installLocations) {
                if (Test-Path $loc) { $installScript = $loc; break }
            }

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
            if (-not (Test-Path $installerPath)) {
                Show-WsusPopup -Message "Installer folder not found: $installerPath" -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $installerCandidates = @("SQLEXPRADV_x64_ENU.exe", "SQLEXPR_x64_ENU.exe")
            $sqlInstaller = $null
            foreach ($name in $installerCandidates) {
                $candidate = Join-Path $installerPath $name
                if (Test-Path $candidate) { $sqlInstaller = $candidate; break }
            }
            if (-not $sqlInstaller) {
                Show-WsusPopup -Message "SQL Express installer not found in $installerPath.`n`nExpected one of: $($installerCandidates -join ', ')" -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $script:InstallPath = $installerPath

            $saPassword = if ($controls.InstallSaPassword) { $controls.InstallSaPassword.Password } else { "" }
            if ([string]::IsNullOrWhiteSpace($saPassword)) {
                Show-WsusPopup -Message "SA password is required." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $saPasswordConfirm = if ($controls.InstallSaPasswordConfirm) { $controls.InstallSaPasswordConfirm.Password } else { "" }
            if ([string]::IsNullOrWhiteSpace($saPasswordConfirm)) {
                Show-WsusPopup -Message "SA password confirmation is required." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            if ($saPassword -ne $saPasswordConfirm) {
                Show-WsusPopup -Message "SA passwords do not match." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }

            $installScriptSafe = Get-EscapedPath $installScript
            $installerPathSafe = Get-EscapedPath $installerPath
            $saUserSafe = $script:SaUser -replace "'", "''"
            # Security: Pass password via environment variable instead of command line
            # This prevents password exposure in process listings and event logs
            $env:WSUS_INSTALL_SA_PASSWORD = $saPassword
            "& '$installScriptSafe' -InstallerPath '$installerPathSafe' -SaUsername '$saUserSafe' -SaPassword `$env:WSUS_INSTALL_SA_PASSWORD -NonInteractive; Remove-Item Env:\WSUS_INSTALL_SA_PASSWORD -ErrorAction SilentlyContinue"
        }
        "restore" {
            $opts = Show-RestoreDialog
            if ($opts.Cancelled) { return }
            if (-not (Test-SafePath $opts.BackupPath)) {
                Show-WsusPopup -Message "Invalid backup path." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $bkp = Get-EscapedPath $opts.BackupPath
            "& '$mgmtSafe' -Restore -ContentPath '$cp' -SqlInstance '$sql' -BackupPath '$bkp'"
        }
        "transfer" {
            $opts = Show-TransferDialog
            if ($opts.Cancelled) { return }
            if (-not (Test-SafePath $opts.SourcePath)) {
                Show-WsusPopup -Message "Invalid source path." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            if (-not (Test-SafePath $opts.DestinationPath)) {
                Show-WsusPopup -Message "Invalid destination path." -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            $src = Get-EscapedPath $opts.SourcePath
            $dst = Get-EscapedPath $opts.DestinationPath
            $Title = "Transfer ($($src) -> $($dst))"
            if ($opts.UseDateFilter -and $opts.DaysOld -gt 0) {
                $Title = "Transfer (differential, $($opts.DaysOld) days)"
                "robocopy `"$src`" `"$dst`" /E /ZB /COPY:DAT /DCOPY:T /R:1 /W:1 /NFL /NDL /MAXAGE:$($opts.DaysOld)"
            } else {
                $Title = "Transfer (full)"
                "robocopy `"$src`" `"$dst`" /E /ZB /COPY:DAT /DCOPY:T /R:1 /W:1 /NFL /NDL"
            }
        }
        "maintenance" {
            $opts = Show-MaintenanceDialog
            if ($opts.Cancelled) { return }
            $Title = "$Title ($($opts.Profile))"
            $maintCmd = "& '$maintSafe' -Unattended -MaintenanceProfile '$($opts.Profile)' -NoTranscript -UseWindowsAuth"
            if ($opts.ExportPath) {
                $exportPathSafe = Get-EscapedPath $opts.ExportPath
                $maintCmd += " -ExportPath '$exportPathSafe'"
            }
            if ($opts.DifferentialPath) {
                $diffPathSafe = Get-EscapedPath $opts.DifferentialPath
                $maintCmd += " -DifferentialExportPath '$diffPathSafe'"
            }
            if ($opts.ExportDays -and $opts.ExportDays -gt 0) {
                $maintCmd += " -ExportDays $($opts.ExportDays)"
            }
            $maintCmd
        }
        "schedule" {
            $opts = Show-ScheduleTaskDialog
            if ($opts.Cancelled) { return }
            if (-not $taskModuleSafe) {
                Show-WsusPopup -Message "Cannot find WsusScheduledTask.psm1`n`nSearched in:`n- $sr\Modules`n- $(Split-Path $sr -Parent)\Modules`n`nMake sure the Modules folder is in the same directory as WsusManager.exe" -Title "Module Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) -SuppressDuplicateSeconds 5 | Out-Null
                Write-Log "ERROR: WsusScheduledTask.psm1 not found"
                return
            }

            $Title = "Schedule Task ($($opts.Schedule))"
            $runAsUser = $opts.RunAsUser -replace "'", "''"
            # Security: Pass password via environment variable instead of command line
            $env:WSUS_TASK_PASSWORD = $opts.Password
            $args = "-Schedule '$($opts.Schedule)' -Time '$($opts.Time)' -MaintenanceProfile '$($opts.Profile)' -RunAsUser '$runAsUser'"
            if ($opts.Schedule -eq "Weekly") {
                $args += " -DayOfWeek '$($opts.DayOfWeek)'"
            } elseif ($opts.Schedule -eq "Monthly") {
                $args += " -DayOfMonth $($opts.DayOfMonth)"
            }

            # Pass password as SecureString via environment variable (not visible in process list)
            # Pipe result to Out-Null to suppress hashtable table output (messages use Write-Host)
            "& { Import-Module '$taskModuleSafe' -Force -DisableNameChecking; `$secPwd = ConvertTo-SecureString `$env:WSUS_TASK_PASSWORD -AsPlainText -Force; New-WsusMaintenanceTask $args -UserPassword `$secPwd | Out-Null; Remove-Item Env:\WSUS_TASK_PASSWORD -ErrorAction SilentlyContinue }"
        }
        "cleanup"     { "& '$mgmtSafe' -Cleanup -Force -SqlInstance '$sql'" }
        "diagnostics" { "`$null = & '$mgmtSafe' -Diagnostics -ContentPath '$cp' -SqlInstance '$sql'" }
        "reset"       { "& '$mgmtSafe' -Reset" }
        default       { "Write-Host 'Unknown: $Id'" }
    }

    # Expand log panel to show output
    if (-not $script:LogExpanded) {
        $controls.LogPanel.Height = 250
        $controls.BtnToggleLog.Content = "Hide"
        $script:LogExpanded = $true
    }

    # Mark operation as running, disable buttons, show cancel button
    $script:OperationRunning = $true
    Disable-OperationButtons
    $controls.BtnCancelOp.Visibility = "Visible"

    Set-Status "Running: $Title"

    # Branch based on Live Terminal mode
    if ($script:LiveTerminalMode) {
        # LIVE TERMINAL MODE: Launch in visible console window
        $controls.LogOutput.Text = "Live Terminal Mode - $Title`r`n`r`nA PowerShell console window has been opened.`r`nYou can interact with the terminal, scroll, and see live output.`r`n`r`nKeystroke refresh is active (sending Enter every 2 seconds to flush output).`r`n`r`nThe console will remain open after completion so you can review the output.`r`nClose the console window when finished, or press any key to close it."

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            # Configure console window size (font size controlled by user's PowerShell defaults)
            $setupConsole = "mode con: cols=80 lines=25; `$Host.UI.RawUI.WindowTitle = 'WSUS Manager - $Title'"
            # =========================================================================
            # AUTO-CLOSE SCRIPT WITH RESPONSIVE KEY HANDLING
            # =========================================================================
            # After operation completes, show a 30-second countdown before auto-closing.
            # User can press ESC or Q to close immediately.
            #
            # KEY HANDLING DESIGN:
            # - Loop runs every 100ms (300 iterations = 30 seconds) for responsive input
            # - Inner while loop drains ALL buffered keystrokes each iteration
            # - Only ESC and Q keys trigger immediate close; Enter is ignored
            # - Enter is ignored because the keystroke timer sends Enter every 2 seconds
            #   to flush PowerShell output buffers, and we don't want those to close the window
            #
            # Previous issue: 1-second sleep between key checks caused "smashing" behavior
            # where users had to press keys multiple times to register input.
            # =========================================================================
            $autoCloseScript = @'
Write-Host ''
Write-Host '=== Operation Complete ===' -ForegroundColor Green
Write-Host ''
Write-Host 'Window will close in 30 seconds. Press ESC or Q to close now...' -ForegroundColor Yellow
$countdown = 300
while ($countdown -gt 0) {
    # Drain all available keys from buffer and check for ESC/Q
    while ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Escape -or $key.Key -eq [ConsoleKey]::Q) {
            $countdown = 0
            break
        }
    }
    if ($countdown -eq 0) { break }
    Start-Sleep -Milliseconds 100
    $countdown--
}
'@
            $wrappedCmd = "$setupConsole; try { $cmd } catch { Write-Host ('ERROR: ' + `$_.Exception.Message) -ForegroundColor Red }; $autoCloseScript"
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$wrappedCmd`""
            $psi.UseShellExecute = $true
            $psi.CreateNoWindow = $false
            $psi.WorkingDirectory = $sr

            $script:CurrentProcess = New-Object System.Diagnostics.Process
            $script:CurrentProcess.StartInfo = $psi
            $script:CurrentProcess.EnableRaisingEvents = $true

            # For UseShellExecute, we can't redirect output but we can still track exit
            $exitHandler = {
                $data = $Event.MessageData
                # Stop all timers
                if ($null -ne $script:OpCheckTimer) {
                    $script:OpCheckTimer.Stop()
                }
                if ($null -ne $script:KeystrokeTimer) {
                    $script:KeystrokeTimer.Stop()
                }
                $data.Window.Dispatcher.Invoke([Action]{
                    $timestamp = Get-Date -Format "HH:mm:ss"
                    $data.Controls.LogOutput.AppendText("`r`n[$timestamp] [+] Console closed - $($data.Title) finished`r`n")
                    # Show completion notification if enabled
                    if ($script:NotificationsEnabled -and (Get-Command Show-WsusNotification -ErrorAction SilentlyContinue)) {
                        $durationSecs = ((Get-Date) - $data.StartTime).TotalSeconds
                        $dur = [TimeSpan]::FromSeconds($durationSecs)
                        Show-WsusNotification -Title "WSUS Manager  - $($data.Title) Complete" -Message "Completed in $([int]$dur.TotalMinutes)m $($dur.Seconds)s" -Result "Pass" -EnableBeep:$script:NotificationBeep
                    }
                    # Record operation history
                    if ($script:HistoryEnabled -and (Get-Command Write-WsusOperationHistory -ErrorAction SilentlyContinue)) {
                        $duration = if ($data.StartTime) { (Get-Date) - $data.StartTime } else { [TimeSpan]::Zero }
                        Write-WsusOperationHistory -OperationType $data.Title -Duration $duration -Result "Pass" -Summary "Completed via GUI"
                    }
                    $data.Controls.StatusLabel.Text = " - Completed at $timestamp"
                    $data.Controls.BtnCancelOp.Visibility = "Collapsed"
                    foreach ($btnName in $data.OperationButtons) {
                        if ($data.Controls[$btnName]) {
                            $data.Controls[$btnName].IsEnabled = $true
                            $data.Controls[$btnName].Opacity = 1.0
                        }
                    }
                    foreach ($inputName in $data.OperationInputs) {
                        if ($data.Controls[$inputName]) {
                            $data.Controls[$inputName].IsEnabled = $true
                            $data.Controls[$inputName].Opacity = 1.0
                        }
                    }
                    # Re-check WSUS installation to disable buttons if WSUS not installed
                    Update-WsusButtonState
                })
                $script:OperationRunning = $false
            }

            $eventData = @{
                Window = $script:window
                Controls = $script:controls
                Title = $Title
                OperationButtons = $script:OperationButtons
                OperationInputs = $script:OperationInputs
                StartTime = Get-Date
            }

            $script:ExitEventJob = Register-ObjectEvent -InputObject $script:CurrentProcess -EventName Exited -Action $exitHandler -MessageData $eventData

            $script:CurrentProcess.Start() | Out-Null

            # Security: Clear password environment variables from parent process immediately after child starts
            # The child process has already inherited these values, so we can safely remove them here
            if ($env:WSUS_INSTALL_SA_PASSWORD) { Remove-Item Env:\WSUS_INSTALL_SA_PASSWORD -ErrorAction SilentlyContinue }
            if ($env:WSUS_TASK_PASSWORD) { Remove-Item Env:\WSUS_TASK_PASSWORD -ErrorAction SilentlyContinue }

            # Give the process a moment to create its window
            Start-Sleep -Milliseconds 500

            # =========================================================================
            # LIVE TERMINAL WINDOW POSITIONING
            # =========================================================================
            # Position the PowerShell console window centered within the main app window.
            # This creates a "nested" visual effect where the terminal appears on top of
            # the main application, making it clear which window the user should interact with.
            #
            # Size: 60% of main window dimensions (with 400x300 minimum)
            #   - Smaller percentages keep the window fully inside the main app
            #   - The 80-column mode (set via 'mode con:') determines text wrapping
            #
            # Position: Centered horizontally and vertically within main window bounds
            #   - Clamped to screen edges to prevent off-screen placement
            #   - 10px/40px margins from screen edges for taskbar visibility
            #
            # Uses Win32 SetWindowPos via ConsoleWindowHelper P/Invoke class
            # =========================================================================
            try {
                $hWnd = $script:CurrentProcess.MainWindowHandle
                if ($hWnd -ne [IntPtr]::Zero) {
                    # Get main window position and size for centering calculation
                    $mainLeft = [int]$script:window.Left
                    $mainTop = [int]$script:window.Top
                    $mainWidth = [int]$script:window.ActualWidth
                    $mainHeight = [int]$script:window.ActualHeight

                    # Console is 60% of main window size (fits centered within app)
                    # Min 400x300 ensures usability on small windows
                    $consoleWidth = [math]::Max(400, [int]($mainWidth * 0.60))
                    $consoleHeight = [math]::Max(300, [int]($mainHeight * 0.60))

                    # Center console within main window
                    $consoleX = $mainLeft + [int](($mainWidth - $consoleWidth) / 2)
                    $consoleY = $mainTop + [int](($mainHeight - $consoleHeight) / 2)

                    # Clamp to screen bounds to prevent off-screen placement
                    $screenWidth = [System.Windows.SystemParameters]::VirtualScreenWidth
                    $screenHeight = [System.Windows.SystemParameters]::VirtualScreenHeight
                    $consoleX = [math]::Max(0, [math]::Min($consoleX, $screenWidth - $consoleWidth - 10))
                    $consoleY = [math]::Max(0, [math]::Min($consoleY, $screenHeight - $consoleHeight - 40))

                    [ConsoleWindowHelper]::PositionWindow($hWnd, $consoleX, $consoleY, $consoleWidth, $consoleHeight)
                }
            } catch {
                # Silently ignore positioning errors - window will just use default position
            }

            # Keystroke timer - sends Enter to console every 2 seconds to flush output buffer
            $script:KeystrokeTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:KeystrokeTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
            $script:KeystrokeTimer.Add_Tick({
                try {
                    if ($null -ne $script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
                        $hWnd = $script:CurrentProcess.MainWindowHandle
                        if ($hWnd -ne [IntPtr]::Zero) {
                            [ConsoleWindowHelper]::SendEnter($hWnd)
                        }
                    } else {
                        $this.Stop()
                    }
                } catch {
                    # Silently ignore keystroke errors
                }
            })
            $script:KeystrokeTimer.Start()

            # Timer for backup cleanup (in case exit event doesn't fire)
            $script:OpCheckTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:OpCheckTimer.Interval = [TimeSpan]::FromMilliseconds(500)
            $script:OpCheckTimer.Add_Tick({
                if ($null -eq $script:CurrentProcess -or $script:CurrentProcess.HasExited) {
                    $this.Stop()
                    if ($null -ne $script:KeystrokeTimer) {
                        $script:KeystrokeTimer.Stop()
                    }
                    if ($script:OperationRunning) {
                        $script:OperationRunning = $false
                        Enable-OperationButtons
                        $script:controls.BtnCancelOp.Visibility = "Collapsed"
                        $timestamp = Get-Date -Format "HH:mm:ss"
                        $script:controls.StatusLabel.Text = " - Completed at $timestamp"
                    }
                }
            })
            $script:OpCheckTimer.Start()

        } catch {
            $controls.LogOutput.AppendText("`r`nERROR: $_`r`n")
            Set-Status "Ready"
            $script:OperationRunning = $false
            Enable-OperationButtons
            $controls.BtnCancelOp.Visibility = "Collapsed"
            if ($null -ne $script:KeystrokeTimer) {
                $script:KeystrokeTimer.Stop()
            }
        }
    } else {
        # EMBEDDED LOG MODE: Capture output to log panel (original behavior)
        $controls.LogOutput.Clear()
        $script:RecentLines = @{}
        Write-LogOutput "Starting $Title..." -Level Info

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.RedirectStandardInput = $true
            $psi.CreateNoWindow = $true
            $psi.WorkingDirectory = $sr

            $script:CurrentProcess = New-Object System.Diagnostics.Process
            $script:CurrentProcess.StartInfo = $psi
            $script:CurrentProcess.EnableRaisingEvents = $true

            # Create shared state object that can be modified from event handlers
            $eventData = @{
                Window = $script:window
                Controls = $script:controls
                Title = $Title
                OperationButtons = $script:OperationButtons
                OperationInputs = $script:OperationInputs
                StartTime = Get-Date
            }

            $outputHandler = {
                $line = $Event.SourceEventArgs.Data
                # Skip empty or whitespace-only lines
                if ([string]::IsNullOrWhiteSpace($line)) { return }

                # Deduplication: Skip if we just saw this exact line (within 2 second window)
                $lineHash = $line.Trim().GetHashCode().ToString()
                $now = [DateTime]::UtcNow.Ticks
                $lastSeen = $script:RecentLines[$lineHash]
                if ($lastSeen -and ($now - $lastSeen) -lt 20000000) {  # 2 seconds in ticks
                    return  # Skip duplicate
                }
                $script:RecentLines[$lineHash] = $now

                $data = $Event.MessageData
                $level = if($line -match 'ERROR|FAIL'){'Error'}elseif($line -match 'WARN'){'Warning'}elseif($line -match 'OK|Success|\[PASS\]|\[\+\]'){'Success'}else{'Info'}
                # Format message BEFORE dispatch to capture values properly
                $timestamp = Get-Date -Format "HH:mm:ss"
                $prefix = switch ($level) { 'Success' { "[+]" } 'Warning' { "[!]" } 'Error' { "[-]" } default { "[*]" } }
                $formattedLine = "[$timestamp] $prefix $line`r`n"
                $logOutput = $data.Controls.LogOutput
                # Use BeginInvoke with closure to capture formatted values
                $data.Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Normal, [Action]{
                    $script:FullLogContent += $formattedLine
                    $logOutput.AppendText($formattedLine)
                    $logOutput.ScrollToEnd()
                }.GetNewClosure())
            }

            $exitHandler = {
                $data = $Event.MessageData
                # Stop all timers IMMEDIATELY to prevent race conditions
                if ($null -ne $script:OpCheckTimer) {
                    $script:OpCheckTimer.Stop()
                }
                if ($null -ne $script:StdinFlushTimer) {
                    $script:StdinFlushTimer.Stop()
                }
                $data.Window.Dispatcher.Invoke([Action]{
                    $timestamp = Get-Date -Format "HH:mm:ss"
                    $line = "[$timestamp] [+] $($data.Title) completed`r`n"
                    $script:FullLogContent += $line
                    $data.Controls.LogOutput.AppendText($line)
                    $data.Controls.LogOutput.ScrollToEnd()
                    # Show completion notification if enabled
                    if ($script:NotificationsEnabled -and (Get-Command Show-WsusNotification -ErrorAction SilentlyContinue)) {
                        $durationSecs = ((Get-Date) - $data.StartTime).TotalSeconds
                        $dur = [TimeSpan]::FromSeconds($durationSecs)
                        Show-WsusNotification -Title "WSUS Manager  - $($data.Title) Complete" -Message "Completed in $([int]$dur.TotalMinutes)m $($dur.Seconds)s" -Result "Pass" -EnableBeep:$script:NotificationBeep
                    }
                    # Record operation history
                    if ($script:HistoryEnabled -and (Get-Command Write-WsusOperationHistory -ErrorAction SilentlyContinue)) {
                        $duration = if ($data.StartTime) { (Get-Date) - $data.StartTime } else { [TimeSpan]::Zero }
                        Write-WsusOperationHistory -OperationType $data.Title -Duration $duration -Result "Pass" -Summary "Completed via GUI"
                    }
                    $data.Controls.StatusLabel.Text = " - Completed at $timestamp"
                    $data.Controls.BtnCancelOp.Visibility = "Collapsed"
                    # Re-enable all operation buttons
                    foreach ($btnName in $data.OperationButtons) {
                        if ($data.Controls[$btnName]) {
                            $data.Controls[$btnName].IsEnabled = $true
                            $data.Controls[$btnName].Opacity = 1.0
                        }
                    }
                    # Re-enable all operation input fields
                    foreach ($inputName in $data.OperationInputs) {
                        if ($data.Controls[$inputName]) {
                            $data.Controls[$inputName].IsEnabled = $true
                            $data.Controls[$inputName].Opacity = 1.0
                        }
                    }
                    # Re-check WSUS installation to disable buttons if WSUS not installed
                    Update-WsusButtonState
                })
                # Reset the operation running flag (script scope accessible from event handler)
                $script:OperationRunning = $false
            }

            # Store event subscriptions for proper cleanup (prevents duplicates/leaks)
            $script:OutputEventJob = Register-ObjectEvent -InputObject $script:CurrentProcess -EventName OutputDataReceived -Action $outputHandler -MessageData $eventData
            $script:ErrorEventJob = Register-ObjectEvent -InputObject $script:CurrentProcess -EventName ErrorDataReceived -Action $outputHandler -MessageData $eventData
            $script:ExitEventJob = Register-ObjectEvent -InputObject $script:CurrentProcess -EventName Exited -Action $exitHandler -MessageData $eventData

            $script:CurrentProcess.Start() | Out-Null

            # Security: Clear password environment variables from parent process immediately after child starts
            # The child process has already inherited these values, so we can safely remove them here
            if ($env:WSUS_INSTALL_SA_PASSWORD) { Remove-Item Env:\WSUS_INSTALL_SA_PASSWORD -ErrorAction SilentlyContinue }
            if ($env:WSUS_TASK_PASSWORD) { Remove-Item Env:\WSUS_TASK_PASSWORD -ErrorAction SilentlyContinue }

            $script:CurrentProcess.BeginOutputReadLine()
            $script:CurrentProcess.BeginErrorReadLine()

            # Stdin flush timer - sends newlines to StandardInput every 2 seconds to flush output buffer
            $script:StdinFlushTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:StdinFlushTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
            $script:StdinFlushTimer.Add_Tick({
                try {
                    if ($null -ne $script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
                        # Write empty line to stdin to help flush any buffered output
                        $script:CurrentProcess.StandardInput.WriteLine("")
                        $script:CurrentProcess.StandardInput.Flush()
                    } else {
                        $this.Stop()
                    }
                } catch {
                    # Silently ignore stdin write errors (process may have exited)
                }
            })
            $script:StdinFlushTimer.Start()

            # Use a timer to force UI refresh (keeps log responsive)
            # Note: Primary cleanup happens in exitHandler; timer is backup for edge cases only
            $script:OpCheckTimer = New-Object System.Windows.Threading.DispatcherTimer
            $script:OpCheckTimer.Interval = [TimeSpan]::FromMilliseconds(250)
            $script:OpCheckTimer.Add_Tick({
                # Force WPF to process pending dispatcher operations (keeps log responsive)
                # This is the WPF equivalent of DoEvents - pushes all queued dispatcher frames
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [Action]{ }
                )

                # Backup cleanup: only if process exited but exitHandler didn't fire
                if ($null -eq $script:CurrentProcess -or $script:CurrentProcess.HasExited) {
                    $this.Stop()
                    if ($null -ne $script:StdinFlushTimer) {
                        $script:StdinFlushTimer.Stop()
                    }
                    # Only do cleanup if exitHandler didn't already (check if still marked as running)
                    if ($script:OperationRunning) {
                        $script:OperationRunning = $false
                        Enable-OperationButtons
                        $script:controls.BtnCancelOp.Visibility = "Collapsed"
                        # Don't overwrite status - exitHandler sets completion timestamp
                    }
                }
            })
            $script:OpCheckTimer.Start()
        } catch {
            Write-LogOutput "ERROR: $_" -Level Error
            Set-Status "Ready"
            $script:OperationRunning = $false
            Enable-OperationButtons
            $controls.BtnCancelOp.Visibility = "Collapsed"
            if ($null -ne $script:StdinFlushTimer) {
                $script:StdinFlushTimer.Stop()
            }
        }
    }
}

#endregion

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
        # Only enable if passwords also match
        $pwdConfirm = $controls.InstallSaPasswordConfirm.Password
        $controls.BtnRunInstall.IsEnabled = ($pwd -eq $pwdConfirm -and $pwd.Length -gt 0)
    }
}.GetNewClosure())

$controls.InstallSaPasswordConfirm.Add_PasswordChanged({
    $pwd = $controls.InstallSaPassword.Password
    $pwdConfirm = $controls.InstallSaPasswordConfirm.Password
    $strength = Test-PasswordStrength $pwd
    $controls.BtnRunInstall.IsEnabled = ($pwd -eq $pwdConfirm -and $strength -eq 100)
}.GetNewClosure())
$controls.BtnRestore.Add_Click({ Invoke-LogOperation "restore" "Restore Database" })
$controls.BtnCreateGpo.Add_Click({
    # Create GPO files for DC admin
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

    # Confirm dialog
    $result = Show-WsusPopup -Message "This will copy GPO files to:`n$destDir`n`nContinue?" -Title "Create GPO Files" -Button ([System.Windows.MessageBoxButton]::YesNo) -Icon ([System.Windows.MessageBoxImage]::Question)

    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }

    # Disable buttons during operation
    Disable-OperationButtons

    # Expand log panel and show progress
    if (-not $script:LogExpanded) {
        $controls.LogPanel.Height = 250
        $controls.BtnToggleLog.Content = "Hide"
        $script:LogExpanded = $true
    }

    Write-LogOutput "=== Creating GPO Files ===" -Level Info

    try {
        # Create destination folder
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            Write-LogOutput "Created folder: $destDir" -Level Success
        }

        # Copy files
        Write-LogOutput "Copying from: $sourceDir" -Level Info
        Copy-Item -Path "$sourceDir\*" -Destination $destDir -Recurse -Force
        Write-LogOutput "Files copied successfully" -Level Success

        # Count items
        $gpoCount = (Get-ChildItem "$destDir\WSUS GPOs" -Directory -ErrorAction SilentlyContinue).Count
        $scriptFile = Test-Path "$destDir\Set-WsusGroupPolicy.ps1"

        Write-LogOutput "GPO backups found: $gpoCount" -Level Info
        Write-LogOutput "Import script: $(if($scriptFile){'Present'}else{'Missing'})" -Level $(if($scriptFile){'Success'}else{'Warning'})

        # Show instructions
        $instructions = @"
GPO files copied to: $destDir

=== NEXT STEPS ===

1. Copy 'C:\WSUS\WSUS GPO' folder to the Domain Controller

2. On the DC, run as Administrator:
   cd 'C:\WSUS\WSUS GPO'
   .\Set-WsusGroupPolicy.ps1 -WsusServerUrl "http://YOURSERVER:8530"

3. To force clients to update immediately:
   gpupdate /force

   Or from DC (all domain computers):
   Get-ADComputer -Filter * | ForEach-Object { Invoke-GPUpdate -Computer `$_.Name -Force }

4. Verify on clients:
   gpresult /r | findstr WSUS
"@

        Write-LogOutput "" -Level Info
        Write-LogOutput "=== INSTRUCTIONS ===" -Level Info
        Write-LogOutput $instructions -Level Info

        Set-Status "GPO files created"

        # Also show message box with summary
        Show-WsusPopup -Message "GPO files created at:`n$destDir`n`nNext steps:`n1. Copy folder to Domain Controller`n2. Run Set-WsusGroupPolicy.ps1 as Admin`n3. Run 'gpupdate /force' on clients`n`nSee log panel for full commands." -Title "GPO Files Created" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Information) | Out-Null

    } catch {
        Write-LogOutput "Error: $_" -Level Error
        Show-WsusPopup -Message "Failed to create GPO files: $_" -Title "Error" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
    } finally {
        # Re-enable buttons (respects WSUS installation status)
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
$controls.BtnDiagnostics.Add_Click({ Invoke-LogOperation "diagnostics" "Diagnostics" })
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
    $controls.HistoryFilter.Add_TextChanged({ Update-HistoryView }.GetNewClosure())
}
if ($controls.BtnClearHistory) {
    $controls.BtnClearHistory.Add_Click({
        if (Get-Command Clear-WsusOperationHistory -ErrorAction SilentlyContinue) {
            Clear-WsusOperationHistory | Out-Null
            Update-HistoryView
        }
    })
}

# Online/Offline status indicator — click to toggle manual override
if ($controls.InternetStatusBorder) {
    $controls.InternetStatusBorder.Add_MouseLeftButtonUp({
        if ($script:ServerModeOverride) {
            # Already manually overridden — toggle to opposite mode
            $script:ServerModeOverride = if ($script:ServerModeOverride -eq "Online") { "Air-Gap" } else { "Online" }
        } else {
            # Currently auto — force override to opposite of current auto mode
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

    $sqlcmdPaths = @(
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\170\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\160\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\150\Tools\Binn\sqlcmd.exe"
    )
    $sqlcmd = $sqlcmdPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $sqlcmd) {
        Write-LogOutput "[Fix SQL Login] ERROR: sqlcmd.exe not found. Is SQL Server installed?" -Level Error
        Show-WsusPopup -Message "sqlcmd.exe not found. SQL Server does not appear to be installed.`n`nRun 'Install WSUS' first." -Title "SQL Not Found" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    try {
        $sqlcmdArgs = @("-S", $sqlInstance, "-E", "-C")

        # Create login if not exists
        $output = & $sqlcmd @sqlcmdArgs -Q "IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name=N'$currentUser') CREATE LOGIN [$currentUser] FROM WINDOWS; PRINT 'Login created';" -b 2>&1
        Write-LogOutput "[Fix SQL Login] $output"

        # Add to sysadmin role
        $output = & $sqlcmd @sqlcmdArgs -Q "ALTER SERVER ROLE [sysadmin] ADD MEMBER [$currentUser]; PRINT 'sysadmin granted';" -b 2>&1
        Write-LogOutput "[Fix SQL Login] $output"

        # Verify
        $check = & $sqlcmd @sqlcmdArgs -Q "SELECT IS_SRVROLEMEMBER('sysadmin', SUSER_SNAME())" -h -1 -W 2>$null
        Write-LogOutput "[Fix SQL Login] Verification (1=sysadmin): $check"

        if ($check -eq 1) {
            Write-LogOutput "[Fix SQL Login] SUCCESS: $currentUser is now a sysadmin on $sqlInstance"
            Show-WsusPopup -Message "$currentUser has been added as sysadmin on $sqlInstance.`n`nYou can now connect to SQL Server." -Title "SQL Login Fixed" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Information) | Out-Null
        } else {
            Write-LogOutput "[Fix SQL Login] WARNING: Verification returned $check" -Level Warning
            Show-WsusPopup -Message "Login may not have been set correctly.`n`nVerification result: $check`nTry running SSMS and connecting manually." -Title "Check Results" -Button ([System.Windows.MessageBoxButton]::OK) -Icon ([System.Windows.MessageBoxImage]::Warning) | Out-Null
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

$controls.QBtnDiagnostics.Add_Click({ Invoke-LogOperation "diagnostics" "Diagnostics" })
$controls.QBtnCleanup.Add_Click({ Invoke-LogOperation "cleanup" "Deep Cleanup" })
$controls.QBtnMaint.Add_Click({ Invoke-LogOperation "maintenance" "Online Sync" })
$controls.QBtnStart.Add_Click({
    $controls.QBtnStart.IsEnabled = $false
    $controls.QBtnStart.Content = "Starting..."
    $controls.QBtnStart.Background = $script:BrushOrange
    Set-Status "Starting services..."

    # Expand log panel
    if (-not $script:LogExpanded) {
        $controls.LogPanel.Height = 250
        $controls.BtnToggleLog.Content = "Hide"
        $script:LogExpanded = $true
    }

    Write-LogOutput "Starting WSUS services..." -Level Info
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
        $controls.LogPanel.Height = 36
        $controls.BtnToggleLog.Content = "Show"
        $script:LogExpanded = $false
    } else {
        $controls.LogPanel.Height = 250
        $controls.BtnToggleLog.Content = "Hide"
        $script:LogExpanded = $true
    }
})

$controls.BtnClearLog.Add_Click({ $controls.LogOutput.Clear() })

$controls.BtnSaveLog.Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "Text Files (*.txt)|*.txt"
    $dialog.FileName = "WsusManager-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    if ($dialog.ShowDialog() -eq $true) {
        $controls.LogOutput.Text | Out-File $dialog.FileName -Encoding UTF8
        Write-LogOutput "Log saved to $($dialog.FileName)" -Level Success
    }
})

#region Log Panel Context Menu
$logContextMenu = New-Object System.Windows.Controls.ContextMenu
$menuCopyAll = New-Object System.Windows.Controls.MenuItem
$menuCopyAll.Header = "Copy All"
$menuCopyAll.Add_Click({
    if ($controls.LogOutput.Text.Length -gt 0) {
        [System.Windows.Clipboard]::SetText($controls.LogOutput.Text)
    }
}.GetNewClosure())
$menuSaveToFile = New-Object System.Windows.Controls.MenuItem
$menuSaveToFile.Header = "Save to File..."
$menuSaveToFile.Add_Click({
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = "Text Files (*.txt)|*.txt"
    $dialog.FileName = "WsusManager-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    if ($dialog.ShowDialog() -eq $true) {
        $controls.LogOutput.Text | Out-File $dialog.FileName -Encoding UTF8
        Write-LogOutput "Log saved to $($dialog.FileName)" -Level Success
    }
}.GetNewClosure())
$null = $logContextMenu.Items.Add($menuCopyAll)
$null = $logContextMenu.Items.Add($menuSaveToFile)
$controls.LogOutput.ContextMenu = $logContextMenu
#endregion

$controls.BtnBack.Add_Click({ Show-Panel "Dashboard" "Dashboard" "BtnDashboard" })
$controls.BtnCancel.Add_Click({
    Stop-CurrentOperation
    Enable-OperationButtons
    $controls.BtnCancel.Visibility = "Collapsed"
    Set-Status "Cancelled"
})
#endregion

#region Initialize
$script:Splash = Show-SplashScreen
Update-SplashProgress -Splash $script:Splash -Progress 20 -Status "Loading interface..."
$controls.VersionLabel.Text = "v$script:AppVersion"
$controls.AboutVersion.Text = "Version $script:AppVersion"

# Initialize Live Terminal button state from saved settings
if ($script:LiveTerminalMode) {
    $controls.BtnLiveTerminal.Content = "Live Terminal: On"
    $controls.BtnLiveTerminal.Background = $script:BrushGreen
    $controls.LogOutput.Text = "Live Terminal Mode enabled.`r`n`r`nOperations will open in a separate PowerShell console window.`r`nYou can interact with the terminal, scroll, and see live output.`r`n`r`nClick 'Live Terminal: On' to switch back to embedded log mode."
}

try {
    $iconPath = Join-Path $script:ScriptRoot "wsus-icon.ico"
    if (-not (Test-Path $iconPath)) { $iconPath = Join-Path (Split-Path -Parent $script:ScriptRoot) "wsus-icon.ico" }
    if (Test-Path $iconPath) {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $iconPath))
    }
} catch { <# Icon load failed - using default #> }

# Load General Atomics logo for sidebar and About page
try {
    $logoPath = Join-Path $script:ScriptRoot "general_atomics_logo_small.ico"
    if (-not (Test-Path $logoPath)) { $logoPath = Join-Path (Split-Path -Parent $script:ScriptRoot) "general_atomics_logo_small.ico" }
    if (Test-Path $logoPath) {
        $logoUri = New-Object System.Uri $logoPath
        $logoBitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $logoBitmap.BeginInit()
        $logoBitmap.UriSource = $logoUri
        $logoBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $logoBitmap.EndInit()
        $controls.SidebarLogo.Source = $logoBitmap
    }
} catch { <# Sidebar logo load failed #> }

try {
    $aboutLogoPath = Join-Path $script:ScriptRoot "general_atomics_logo_big.ico"
    if (-not (Test-Path $aboutLogoPath)) { $aboutLogoPath = Join-Path (Split-Path -Parent $script:ScriptRoot) "general_atomics_logo_big.ico" }
    if (-not (Test-Path $aboutLogoPath)) { $aboutLogoPath = Join-Path $script:ScriptRoot "general_atomics_logo_small.ico" }
    if (-not (Test-Path $aboutLogoPath)) { $aboutLogoPath = Join-Path (Split-Path -Parent $script:ScriptRoot) "general_atomics_logo_small.ico" }
    if (Test-Path $aboutLogoPath) {
        $aboutUri = New-Object System.Uri $aboutLogoPath
        $aboutBitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $aboutBitmap.BeginInit()
        $aboutBitmap.UriSource = $aboutUri
        $aboutBitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $aboutBitmap.EndInit()
        $controls.AboutLogo.Source = $aboutBitmap
    }
} catch { <# About logo load failed #> }

Update-SplashProgress -Splash $script:Splash -Progress 60 -Status "Checking services..."
Invoke-DashboardRefreshSafe -Source "Startup"
Update-SplashProgress -Splash $script:Splash -Progress 90 -Status "Starting..."

# Show message if WSUS is not installed
if (-not $script:WsusInstalled) {
    $controls.LogOutput.Text = "WSUS is not installed on this server.`r`n`r`nMost operations are disabled until WSUS is installed.`r`nUse 'Install WSUS' from the Setup menu to begin installation.`r`n"
    # Expand log panel to show message
    $controls.LogPanel.Height = 250
    $controls.BtnToggleLog.Content = "Hide"
    $script:LogExpanded = $true
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
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
    # Load app icon for tray; fall back to built-in application icon
    $iconPath = Join-Path $script:ScriptRoot "wsus-icon.ico"
    if (-not (Test-Path $iconPath)) { $iconPath = Join-Path (Split-Path -Parent $script:ScriptRoot) "wsus-icon.ico" }
    if (Test-Path $iconPath) {
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
        } catch {}
        $script:TrayIcon = $null
    }
    # Clean up any running operation (suppress log since we're closing)
    Stop-CurrentOperation -SuppressLog
})
#endregion

#region Main Entry Point with Error Handling
$script:StartupDuration = ((Get-Date) - $script:StartupTime).TotalMilliseconds
Write-Log "Startup completed in $([math]::Round($script:StartupDuration, 0))ms"
Write-Log "Running WPF form"

if ($null -ne $script:Splash) {
    Update-SplashProgress -Splash $script:Splash -Progress 100 -Status "Ready"
    Start-Sleep -Milliseconds 300
    try { $script:Splash.Window.Close() } catch {}
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
        # Silently ignore cleanup errors during shutdown
    }
}

Write-Log "=== Application closed ==="
#endregion

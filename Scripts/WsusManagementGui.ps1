#Requires -Version 5.1
<#
===============================================================================
Script: WsusManagementGui.ps1
Author: Tony Tran, ISSO, Classified Computing, GA-ASI
Version: 3.8.6
===============================================================================
.SYNOPSIS
    WSUS Manager GUI - Modern WPF interface for WSUS management
.DESCRIPTION
    Portable GUI for managing WSUS servers with SQL Express.
    Features: Dashboard, Health checks, Maintenance, Import/Export
#>

# No parameters - admin check always runs

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

$script:AppVersion = "3.8.7"
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
$script:RefreshInProgress = $false
$script:CurrentProcess = $null
$script:OperationRunning = $false
# Event subscription tracking for proper cleanup (prevents duplicates/leaks)
$script:OutputEventJob = $null
$script:ErrorEventJob = $null
$script:ExitEventJob = $null
$script:OpCheckTimer = $null
# Deduplication tracking - prevents same line appearing multiple times
$script:RecentLines = @{}
# Live Terminal Mode - launches operations in visible console window
$script:LiveTerminalMode = $false

function Write-Log { param([string]$Msg)
    try {
        if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
        "[$(Get-Date -Format 'HH:mm:ss')] $Msg" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch { <# Silently ignore logging failures #> }
}

function Import-WsusSettings {
    try {
        if (Test-Path $script:SettingsFile) {
            $s = Get-Content $script:SettingsFile -Raw | ConvertFrom-Json
            if ($s.ContentPath) { $script:ContentPath = $s.ContentPath }
            if ($s.SqlInstance) { $script:SqlInstance = $s.SqlInstance }
            if ($s.ExportRoot) { $script:ExportRoot = $s.ExportRoot }
            if ($s.ServerMode) { $script:ServerMode = $s.ServerMode }
            if ($null -ne $s.LiveTerminalMode) { $script:LiveTerminalMode = $s.LiveTerminalMode }
        }
    } catch { Write-Log "Failed to load settings: $_" }
}

function Save-Settings {
    try {
        $dir = Split-Path $script:SettingsFile -Parent
        if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        @{ ContentPath=$script:ContentPath; SqlInstance=$script:SqlInstance; ExportRoot=$script:ExportRoot; ServerMode=$script:ServerMode; LiveTerminalMode=$script:LiveTerminalMode } |
            ConvertTo-Json | Set-Content $script:SettingsFile -Encoding UTF8
    } catch { Write-Log "Failed to save settings: $_" }
}

Import-WsusSettings
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
        Title="WSUS Manager" Height="720" Width="950" MinHeight="600" MinWidth="800"
        WindowStartupLocation="CenterScreen" Background="#0D1117">
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
        <SolidColorBrush x:Key="Text3" Color="#484F58"/>

        <Style x:Key="NavBtn" TargetType="Button">
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
                        <Border x:Name="bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}" CornerRadius="4" Margin="4,1">
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
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
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
                                <Setter Property="Foreground" Value="#484F58"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="BtnSec" TargetType="Button" BasedOn="{StaticResource Btn}">
            <Setter Property="Background" Value="{StaticResource BgCard}"/>
            <Setter Property="Foreground" Value="{StaticResource Text1}"/>
            <Setter Property="FontWeight" Value="Normal"/>
        </Style>

        <Style x:Key="BtnGreen" TargetType="Button" BasedOn="{StaticResource Btn}">
            <Setter Property="Background" Value="{StaticResource Green}"/>
        </Style>

        <Style x:Key="BtnRed" TargetType="Button" BasedOn="{StaticResource Btn}">
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
                        <Image x:Name="SidebarLogo" Width="32" Height="32" Margin="0,0,10,0" VerticalAlignment="Center"/>
                        <StackPanel VerticalAlignment="Center">
                            <TextBlock Text="WSUS Manager" FontSize="15" FontWeight="Bold" Foreground="{StaticResource Text1}"/>
                            <TextBlock x:Name="VersionLabel" Text="v3.8.3" FontSize="10" Foreground="{StaticResource Text3}" Margin="0,2,0,0"/>
                        </StackPanel>
                    </StackPanel>

                </StackPanel>

                <StackPanel DockPanel.Dock="Bottom" Margin="4,0,4,12">
                    <Button x:Name="BtnHelp" Content="? Help" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnSettings" Content="⚙ Settings" Style="{StaticResource NavBtn}"/>
                    <Button x:Name="BtnAbout" Content="ℹ About" Style="{StaticResource NavBtn}"/>
                </StackPanel>

                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
                    <StackPanel>
                        <Button x:Name="BtnDashboard" Content="◉ Dashboard" Style="{StaticResource NavBtn}" Background="#21262D" Foreground="{StaticResource Text1}"/>

                        <TextBlock Text="SETUP" FontSize="9" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,14,0,4"/>
                        <Button x:Name="BtnInstall" Content="▶ Install WSUS" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnRestore" Content="↻ Restore DB" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnCreateGpo" Content="📋 Create GPO" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="TRANSFER" FontSize="9" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,14,0,4"/>
                        <Button x:Name="BtnTransfer" Content="⇄ Export/Import" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="MAINTENANCE" FontSize="9" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,14,0,4"/>
                        <Button x:Name="BtnMaintenance" Content="📅 Monthly" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnSchedule" Content="⏰ Schedule Task" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnCleanup" Content="🧹 Cleanup" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="DIAGNOSTICS" FontSize="9" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,14,0,4"/>
                        <Button x:Name="BtnHealth" Content="🔍 Health Check" Style="{StaticResource NavBtn}"/>
                        <Button x:Name="BtnRepair" Content="🔧 Repair" Style="{StaticResource NavBtn}"/>
                    </StackPanel>
                </ScrollViewer>
            </DockPanel>
        </Border>

        <!-- Main Content -->
        <Grid Grid.Column="1" Margin="20,12">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <DockPanel Margin="0,0,0,12">
                <Border DockPanel.Dock="Right" Background="{StaticResource BgCard}" CornerRadius="4" Padding="8,4">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Ellipse x:Name="InternetStatusDot" Width="8" Height="8" Fill="{StaticResource Red}" Margin="0,0,6,0"/>
                        <TextBlock x:Name="InternetStatusText" Text="Offline" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource Text2}"/>
                    </StackPanel>
                </Border>
                <TextBlock x:Name="PageTitle" Text="Dashboard" FontSize="20" FontWeight="Bold" Foreground="{StaticResource Text1}" VerticalAlignment="Center"/>
            </DockPanel>

            <!-- Dashboard Panel -->
            <Grid x:Name="DashboardPanel" Grid.Row="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Status Cards -->
                <UniformGrid Rows="1" Margin="0,0,0,16">
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="0,0,8,0">
                        <Grid>
                            <Border x:Name="Card1Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Blue}"/>
                            <StackPanel Margin="12,14,12,12">
                                <TextBlock Text="Services" FontSize="10" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card1Value" Text="..." FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card1Sub" Text="SQL, WSUS, IIS" FontSize="9" Foreground="{StaticResource Text3}" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card2Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Green}"/>
                            <StackPanel Margin="12,14,12,12">
                                <TextBlock Text="Database" FontSize="10" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card2Value" Text="..." FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card2Sub" Text="SUSDB" FontSize="9" Foreground="{StaticResource Text3}" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="4,0">
                        <Grid>
                            <Border x:Name="Card3Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Orange}"/>
                            <StackPanel Margin="12,14,12,12">
                                <TextBlock Text="Disk" FontSize="10" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card3Value" Text="..." FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card3Sub" Text="Free space" FontSize="9" Foreground="{StaticResource Text3}" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Margin="8,0,0,0">
                        <Grid>
                            <Border x:Name="Card4Bar" Height="3" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource Blue}"/>
                            <StackPanel Margin="12,14,12,12">
                                <TextBlock Text="Task" FontSize="10" Foreground="{StaticResource Text2}"/>
                                <TextBlock x:Name="Card4Value" Text="..." FontSize="16" FontWeight="Bold" Foreground="{StaticResource Text1}" Margin="0,4,0,0"/>
                                <TextBlock x:Name="Card4Sub" Text="Scheduled" FontSize="9" Foreground="{StaticResource Text3}" Margin="0,2,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </UniformGrid>

                <!-- Quick Actions -->
                <StackPanel Grid.Row="1" Margin="0,0,0,16">
                    <TextBlock Text="Quick Actions" FontSize="12" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                    <WrapPanel>
                        <Button x:Name="QBtnHealth" Content="Health Check" Style="{StaticResource Btn}" Margin="0,0,6,0"/>
                        <Button x:Name="QBtnCleanup" Content="Deep Cleanup" Style="{StaticResource BtnSec}" Margin="0,0,6,0"/>
                        <Button x:Name="QBtnMaint" Content="Maintenance" Style="{StaticResource BtnSec}" Margin="0,0,6,0"/>
                        <Button x:Name="QBtnStart" Content="Start Services" Style="{StaticResource BtnGreen}"/>
                    </WrapPanel>
                </StackPanel>

                <!-- Config -->
                <Border Grid.Row="2" Background="{StaticResource BgCard}" CornerRadius="4" Padding="14" VerticalAlignment="Top">
                    <StackPanel>
                        <TextBlock Text="Configuration" FontSize="12" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,10"/>
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
                            <TextBlock Text="Content:" Foreground="{StaticResource Text2}" FontSize="11"/>
                            <TextBlock x:Name="CfgContentPath" Grid.Column="1" Text="C:\WSUS" Foreground="{StaticResource Text1}" FontSize="11"/>
                            <TextBlock Grid.Row="1" Text="SQL:" Foreground="{StaticResource Text2}" FontSize="11" Margin="0,4,0,0"/>
                            <TextBlock x:Name="CfgSqlInstance" Grid.Row="1" Grid.Column="1" Text=".\SQLEXPRESS" Foreground="{StaticResource Text1}" FontSize="11" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="2" Text="Export:" Foreground="{StaticResource Text2}" FontSize="11" Margin="0,4,0,0"/>
                            <TextBlock x:Name="CfgExportRoot" Grid.Row="2" Grid.Column="1" Text="C:\" Foreground="{StaticResource Text1}" FontSize="11" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="3" Text="Logs:" Foreground="{StaticResource Text2}" FontSize="11" Margin="0,4,0,0"/>
                            <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" Margin="0,4,0,0">
                                <TextBlock x:Name="CfgLogPath" Foreground="{StaticResource Text1}" FontSize="11"/>
                                <Button x:Name="BtnOpenLog" Content="Open" FontSize="9" Padding="6,1" Margin="8,0,0,0" Background="#30363D" Foreground="{StaticResource Text2}" BorderThickness="0" Cursor="Hand"/>
                            </StackPanel>
                        </Grid>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Install Panel -->
            <Grid x:Name="InstallPanel" Grid.Row="1" Visibility="Collapsed">
                <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16">
                    <StackPanel>
                        <TextBlock Text="Install WSUS + SQL Express" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                        <TextBlock Text="Select the folder containing SQL Server installers. Default is C:\WSUS\SQLDB." FontSize="11" Foreground="{StaticResource Text2}" TextWrapping="Wrap" Margin="0,0,0,12"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="InstallPathBox" Height="28" Background="{StaticResource BgDark}" Foreground="{StaticResource Text1}" BorderThickness="1" BorderBrush="{StaticResource Border}" Padding="6,4"/>
                            <Button x:Name="BtnBrowseInstallPath" Grid.Column="1" Content="Browse" Style="{StaticResource BtnSec}" Padding="10,6" Margin="8,0,0,0"/>
                        </Grid>
                        <TextBlock Text="SA Password:" FontSize="11" Foreground="{StaticResource Text2}" Margin="0,12,0,4"/>
                        <PasswordBox x:Name="InstallSaPassword" Height="28" Background="{StaticResource BgDark}" Foreground="{StaticResource Text1}" BorderThickness="1" BorderBrush="{StaticResource Border}" Padding="6,4"/>
                        <TextBlock Text="Confirm SA Password:" FontSize="11" Foreground="{StaticResource Text2}" Margin="0,12,0,4"/>
                        <PasswordBox x:Name="InstallSaPasswordConfirm" Height="28" Background="{StaticResource BgDark}" Foreground="{StaticResource Text1}" BorderThickness="1" BorderBrush="{StaticResource Border}" Padding="6,4"/>
                        <TextBlock Text="Password must be 15+ chars with a number and special character." FontSize="10" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                        <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
                            <Button x:Name="BtnRunInstall" Content="Install WSUS" Style="{StaticResource BtnGreen}" Margin="0,0,8,0"/>
                            <TextBlock Text="Requires admin rights" FontSize="10" Foreground="{StaticResource Text3}" VerticalAlignment="Center"/>
                        </StackPanel>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- Operation Panel -->
            <Grid x:Name="OperationPanel" Grid.Row="1" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Border Background="{StaticResource BgCard}" CornerRadius="4">
                    <ScrollViewer x:Name="ConsoleScroller" VerticalScrollBarVisibility="Auto" Margin="10">
                        <TextBlock x:Name="ConsoleOutput" FontFamily="Consolas" FontSize="11" Foreground="{StaticResource Text2}" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </Border>
                <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                    <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource BtnRed}" Margin="0,0,8,0" Visibility="Collapsed"/>
                    <Button x:Name="BtnBack" Content="Back" Style="{StaticResource BtnSec}"/>
                </StackPanel>
            </Grid>

            <!-- About Panel -->
            <ScrollViewer x:Name="AboutPanel" Grid.Row="1" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                <StackPanel>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16" Margin="0,0,0,12">
                        <StackPanel Orientation="Horizontal">
                            <Image x:Name="AboutLogo" Width="56" Height="56" Margin="0,0,16,0" VerticalAlignment="Center"/>
                            <StackPanel VerticalAlignment="Center">
                                <TextBlock Text="WSUS Manager" FontSize="18" FontWeight="Bold" Foreground="{StaticResource Text1}"/>
                                <TextBlock x:Name="AboutVersion" Text="Version 3.6.0" FontSize="12" Foreground="{StaticResource Text2}" Margin="0,4,0,0"/>
                                <TextBlock Text="Windows Server Update Services Management Tool" FontSize="11" Foreground="{StaticResource Text3}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16" Margin="0,0,0,12">
                        <StackPanel>
                            <TextBlock Text="Author" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                            <TextBlock Text="Tony Tran" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource Blue}"/>
                            <TextBlock Text="ISSO, Classified Computing, GA-ASI" FontSize="11" Foreground="{StaticResource Text2}" Margin="0,2,0,0"/>
                            <TextBlock Text="tony.tran@ga-asi.com" FontSize="11" Foreground="{StaticResource Blue}" Margin="0,6,0,0"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16" Margin="0,0,0,12">
                        <StackPanel>
                            <TextBlock Text="Features" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                            <TextBlock TextWrapping="Wrap" FontSize="11" Foreground="{StaticResource Text2}" Text="• Automated WSUS + SQL Express installation&#x0a;• Database backup/restore operations&#x0a;• Air-gapped network export/import&#x0a;• Monthly maintenance automation&#x0a;• Health diagnostics with auto-repair&#x0a;• Deep cleanup and optimization"/>
                        </StackPanel>
                    </Border>
                    <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="16">
                        <StackPanel>
                            <TextBlock Text="Requirements" FontSize="13" FontWeight="SemiBold" Foreground="{StaticResource Text1}" Margin="0,0,0,8"/>
                            <TextBlock TextWrapping="Wrap" FontSize="11" Foreground="{StaticResource Text2}" Text="• Windows Server 2019+&#x0a;• PowerShell 5.1+&#x0a;• SQL Server Express 2022&#x0a;• 50GB+ disk space"/>
                            <TextBlock Text="© 2026 GA-ASI. Internal use only." FontSize="10" Foreground="{StaticResource Text3}" Margin="0,12,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <!-- Help Panel -->
            <Grid x:Name="HelpPanel" Grid.Row="1" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Border Background="{StaticResource BgCard}" CornerRadius="4" Padding="10" Margin="0,0,0,12">
                    <WrapPanel>
                        <Button x:Name="HelpBtnOverview" Content="Overview" Style="{StaticResource BtnSec}" Padding="10,5" Margin="0,0,6,0"/>
                        <Button x:Name="HelpBtnDashboard" Content="Dashboard" Style="{StaticResource BtnSec}" Padding="10,5" Margin="0,0,6,0"/>
                        <Button x:Name="HelpBtnOperations" Content="Operations" Style="{StaticResource BtnSec}" Padding="10,5" Margin="0,0,6,0"/>
                        <Button x:Name="HelpBtnAirGap" Content="Air-Gap" Style="{StaticResource BtnSec}" Padding="10,5" Margin="0,0,6,0"/>
                        <Button x:Name="HelpBtnTroubleshooting" Content="Troubleshooting" Style="{StaticResource BtnSec}" Padding="10,5"/>
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

            <!-- Log Panel -->
            <Border x:Name="LogPanel" Grid.Row="2" Background="{StaticResource BgSidebar}" CornerRadius="4" Margin="0,12,0,0" Height="250">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Border Background="{StaticResource BgCard}" Padding="10,6" CornerRadius="4,4,0,0">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Orientation="Horizontal">
                                <TextBlock Text="Output Log" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource Text1}" VerticalAlignment="Center"/>
                                <TextBlock x:Name="StatusLabel" Text=" - Ready" FontSize="10" Foreground="{StaticResource Text2}" VerticalAlignment="Center" Margin="8,0,0,0"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button x:Name="BtnCancelOp" Content="Cancel" Background="#F85149" Foreground="White" BorderThickness="0" Padding="8,3" FontSize="10" Margin="0,0,6,0" Visibility="Collapsed"/>
                                <Button x:Name="BtnLiveTerminal" Content="Live Terminal: Off" Style="{StaticResource BtnSec}" Padding="8,3" FontSize="10" Margin="0,0,6,0" ToolTip="Toggle between embedded log and live PowerShell console"/>
                                <Button x:Name="BtnToggleLog" Content="Hide" Style="{StaticResource BtnSec}" Padding="8,3" FontSize="10" Margin="0,0,6,0"/>
                                <Button x:Name="BtnClearLog" Content="Clear" Style="{StaticResource BtnSec}" Padding="8,3" FontSize="10" Margin="0,0,6,0"/>
                                <Button x:Name="BtnSaveLog" Content="Save" Style="{StaticResource BtnSec}" Padding="8,3" FontSize="10"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <TextBox x:Name="LogOutput" Grid.Row="1" IsReadOnly="True" TextWrapping="NoWrap"
                             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                             FontFamily="Consolas" FontSize="11" Background="{StaticResource BgDark}"
                             Foreground="{StaticResource Text2}" BorderThickness="0" Padding="10,8"/>
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

#region Helper Functions
$script:LogExpanded = $true

function Write-LogOutput {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')][string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) { 'Success' { "[+]" } 'Warning' { "[!]" } 'Error' { "[-]" } default { "[*]" } }
    $controls.LogOutput.Dispatcher.Invoke([Action]{
        $controls.LogOutput.AppendText("[$timestamp] $prefix $Message`r`n")
        $controls.LogOutput.ScrollToEnd()
    })
}

function Set-Status {
    param([string]$Text)
    $controls.StatusLabel.Dispatcher.Invoke([Action]{
        $controls.StatusLabel.Text = " - $Text"
    })
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
    $isOnline = Test-InternetConnection
    $script:ServerMode = if ($isOnline) { "Online" } else { "Air-Gap" }

    if ($controls.InternetStatusDot -and $controls.InternetStatusText) {
        $controls.InternetStatusDot.Fill = if ($isOnline) { $window.FindResource("Green") } else { $window.FindResource("Red") }
        $controls.InternetStatusText.Text = if ($isOnline) { "Online" } else { "Offline" }
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

    # Check WSUS installation and update button states
    Update-WsusButtonState
}

function Set-ActiveNavButton {
    param([string]$Active)
    $navBtns = @("BtnDashboard","BtnInstall","BtnRestore","BtnCreateGpo","BtnTransfer","BtnMaintenance","BtnSchedule","BtnCleanup","BtnHealth","BtnRepair","BtnAbout","BtnHelp")
    foreach ($b in $navBtns) {
        if ($controls[$b]) {
            $controls[$b].Background = if($b -eq $Active){"#21262D"}else{"Transparent"}
            $controls[$b].Foreground = if($b -eq $Active){"#E6EDF3"}else{"#8B949E"}
        }
    }
}

# Operation buttons that should be disabled during operations
$script:OperationButtons = @("BtnInstall","BtnRestore","BtnCreateGpo","BtnTransfer","BtnMaintenance","BtnSchedule","BtnCleanup","BtnHealth","BtnRepair","QBtnHealth","QBtnCleanup","QBtnMaint","QBtnStart","BtnRunInstall","BtnBrowseInstallPath")
# Input fields that should be disabled during operations
$script:OperationInputs = @("InstallSaPassword","InstallSaPasswordConfirm","InstallPathBox")
# Buttons that require WSUS to be installed (all except Install WSUS)
$script:WsusRequiredButtons = @("BtnRestore","BtnCreateGpo","BtnTransfer","BtnMaintenance","BtnSchedule","BtnCleanup","BtnHealth","BtnRepair","QBtnHealth","QBtnCleanup","QBtnMaint","QBtnStart")
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
    Set-ActiveNavButton $NavBtn
    if ($Panel -eq "Dashboard") { Update-Dashboard }
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
• 50+ GB disk space

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
• Green: >50GB | Orange: 10-50GB | Red: <10GB

TASK CARD
• Green: Scheduled task ready
• Orange: Not configured

QUICK ACTIONS
• Health Check - Diagnostics only
• Deep Cleanup - Aggressive cleanup
• Maintenance - Monthly routine
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
• Full: Complete DB + all files (50+ GB)
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
• Run Monthly Maintenance

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
    $dlg.Title = "Export to Media"
    $dlg.Width = 450
    $dlg.Height = 340
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Export WSUS Data"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    $radioPanel = New-Object System.Windows.Controls.StackPanel
    $radioPanel.Orientation = "Horizontal"
    $radioPanel.Margin = "0,0,0,12"

    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full Export"
    $radioFull.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioFull.IsChecked = $true
    $radioFull.Margin = "0,0,20,0"
    $radioPanel.Children.Add($radioFull)

    $radioDiff = New-Object System.Windows.Controls.RadioButton
    $radioDiff.Content = "Differential"
    $radioDiff.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioPanel.Children.Add($radioDiff)
    $stack.Children.Add($radioPanel)

    $daysPanel = New-Object System.Windows.Controls.StackPanel
    $daysPanel.Orientation = "Horizontal"
    $daysPanel.Margin = "0,0,0,12"
    $daysPanel.Visibility = "Collapsed"

    $daysLbl = New-Object System.Windows.Controls.TextBlock
    $daysLbl.Text = "Days:"
    $daysLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $daysLbl.VerticalAlignment = "Center"
    $daysLbl.Margin = "0,0,8,0"
    $daysPanel.Children.Add($daysLbl)

    $daysTxt = New-Object System.Windows.Controls.TextBox
    $daysTxt.Text = "30"
    $daysTxt.Width = 50
    $daysTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $daysTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $daysTxt.Padding = "4"
    $daysPanel.Children.Add($daysTxt)
    $stack.Children.Add($daysPanel)

    $radioDiff.Add_Checked({ $daysPanel.Visibility = "Visible" }.GetNewClosure())
    $radioFull.Add_Checked({ $daysPanel.Visibility = "Collapsed" }.GetNewClosure())

    $destLbl = New-Object System.Windows.Controls.TextBlock
    $destLbl.Text = "Destination:"
    $destLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $destLbl.Margin = "0,0,0,6"
    $stack.Children.Add($destLbl)

    $destPanel = New-Object System.Windows.Controls.DockPanel
    $destPanel.Margin = "0,0,0,20"

    $destBtn = New-Object System.Windows.Controls.Button
    $destBtn.Content = "Browse"
    $destBtn.Padding = "10,4"
    $destBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $destBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $destBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($destBtn, "Right")
    $destPanel.Children.Add($destBtn)

    $destTxt = New-Object System.Windows.Controls.TextBox
    $destTxt.Margin = "0,0,8,0"
    $destTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $destTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $destTxt.Padding = "6,4"
    $destPanel.Children.Add($destTxt)

    $destBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($fbd.ShowDialog() -eq "OK") { $destTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())
    $stack.Children.Add($destPanel)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $exportBtn = New-Object System.Windows.Controls.Button
    $exportBtn.Content = "Export"
    $exportBtn.Padding = "14,6"
    $exportBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
    $exportBtn.Foreground = "White"
    $exportBtn.BorderThickness = 0
    $exportBtn.Margin = "0,0,8,0"
    $exportBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($destTxt.Text)) {
            [System.Windows.MessageBox]::Show("Select destination folder.", "Export", "OK", "Warning")
            return
        }
        $daysVal = 30
        if ($radioDiff.IsChecked -and -not [int]::TryParse($daysTxt.Text, [ref]$daysVal)) {
            [System.Windows.MessageBox]::Show("Invalid days value.", "Export", "OK", "Warning")
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
    $cancelBtn.Padding = "14,6"
    $cancelBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $cancelBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
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
    $dlg.Title = "Import from Media"
    $dlg.Width = 450
    $dlg.Height = 300
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Import WSUS Data"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    # Source folder section
    $srcLbl = New-Object System.Windows.Controls.TextBlock
    $srcLbl.Text = "Source folder (external media):"
    $srcLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $srcLbl.Margin = "0,0,0,6"
    $stack.Children.Add($srcLbl)

    $srcPanel = New-Object System.Windows.Controls.DockPanel
    $srcPanel.Margin = "0,0,0,16"

    $srcBtn = New-Object System.Windows.Controls.Button
    $srcBtn.Content = "Browse"
    $srcBtn.Padding = "10,4"
    $srcBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $srcBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $srcBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($srcBtn, "Right")
    $srcPanel.Children.Add($srcBtn)

    $srcTxt = New-Object System.Windows.Controls.TextBox
    $srcTxt.Margin = "0,0,8,0"
    $srcTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $srcTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $srcTxt.Padding = "6,4"
    $srcPanel.Children.Add($srcTxt)

    $srcBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select source folder containing WSUS export data"
        if ($fbd.ShowDialog() -eq "OK") { $srcTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())
    $stack.Children.Add($srcPanel)

    # Destination folder section
    $dstLbl = New-Object System.Windows.Controls.TextBlock
    $dstLbl.Text = "Destination folder (WSUS server):"
    $dstLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $dstLbl.Margin = "0,0,0,6"
    $stack.Children.Add($dstLbl)

    $dstPanel = New-Object System.Windows.Controls.DockPanel
    $dstPanel.Margin = "0,0,0,20"

    $dstBtn = New-Object System.Windows.Controls.Button
    $dstBtn.Content = "Browse"
    $dstBtn.Padding = "10,4"
    $dstBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $dstBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $dstBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($dstBtn, "Right")
    $dstPanel.Children.Add($dstBtn)

    $dstTxt = New-Object System.Windows.Controls.TextBox
    $dstTxt.Text = "C:\WSUS"
    $dstTxt.Margin = "0,0,8,0"
    $dstTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $dstTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $dstTxt.Padding = "6,4"
    $dstPanel.Children.Add($dstTxt)

    $dstBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select destination folder on WSUS server"
        $fbd.SelectedPath = $dstTxt.Text
        if ($fbd.ShowDialog() -eq "OK") { $dstTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())
    $stack.Children.Add($dstPanel)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $importBtn = New-Object System.Windows.Controls.Button
    $importBtn.Content = "Import"
    $importBtn.Padding = "14,6"
    $importBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
    $importBtn.Foreground = "White"
    $importBtn.BorderThickness = 0
    $importBtn.Margin = "0,0,8,0"
    $importBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($srcTxt.Text)) {
            [System.Windows.MessageBox]::Show("Select source folder.", "Import", "OK", "Warning")
            return
        }
        if ([string]::IsNullOrWhiteSpace($dstTxt.Text)) {
            [System.Windows.MessageBox]::Show("Select destination folder.", "Import", "OK", "Warning")
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
    $cancelBtn.Padding = "14,6"
    $cancelBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $cancelBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
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
    $dlg.Title = "Restore Database"
    $dlg.Width = 550
    $dlg.Height = 320
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Restore WSUS Database"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    # Backup file selection
    $fileLbl = New-Object System.Windows.Controls.TextBlock
    $fileLbl.Text = "Backup file:"
    $fileLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $fileLbl.Margin = "0,0,0,6"
    $stack.Children.Add($fileLbl)

    $filePanel = New-Object System.Windows.Controls.DockPanel
    $filePanel.Margin = "0,0,0,12"

    $browseBtn = New-Object System.Windows.Controls.Button
    $browseBtn.Content = "Browse"
    $browseBtn.Padding = "10,4"
    $browseBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $browseBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $browseBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($browseBtn, "Right")
    $filePanel.Children.Add($browseBtn)

    $fileTxt = New-Object System.Windows.Controls.TextBox
    $fileTxt.Margin = "0,0,8,0"
    $fileTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $fileTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $fileTxt.Padding = "6,4"
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
        $recentLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
        $recentLbl.Margin = "0,0,0,6"
        $stack.Children.Add($recentLbl)

        $listBox = New-Object System.Windows.Controls.ListBox
        $listBox.MaxHeight = 100
        $listBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
        $listBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
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
        $noFilesLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#D29922")
        $noFilesLbl.TextWrapping = "Wrap"
        $noFilesLbl.Margin = "0,0,0,12"
        $stack.Children.Add($noFilesLbl)
    }

    # Warning message
    $warnLbl = New-Object System.Windows.Controls.TextBlock
    $warnLbl.Text = "Warning: This will replace the current SUSDB database!"
    $warnLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F85149")
    $warnLbl.FontWeight = "SemiBold"
    $warnLbl.Margin = "0,0,0,16"
    $stack.Children.Add($warnLbl)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $restoreBtn = New-Object System.Windows.Controls.Button
    $restoreBtn.Content = "Restore"
    $restoreBtn.Padding = "14,6"
    $restoreBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#F85149")
    $restoreBtn.Foreground = "White"
    $restoreBtn.BorderThickness = 0
    $restoreBtn.Margin = "0,0,8,0"
    $restoreBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($fileTxt.Text)) {
            [System.Windows.MessageBox]::Show("Select a backup file.", "Restore", "OK", "Warning")
            return
        }
        if (-not (Test-Path $fileTxt.Text)) {
            [System.Windows.MessageBox]::Show("Backup file not found: $($fileTxt.Text)", "Restore", "OK", "Error")
            return
        }
        $confirm = [System.Windows.MessageBox]::Show("Are you sure you want to restore from:`n$($fileTxt.Text)`n`nThis will replace the current database!", "Confirm Restore", "YesNo", "Warning")
        if ($confirm -eq "Yes") {
            $result.Cancelled = $false
            $result.BackupPath = $fileTxt.Text
            $dlg.Close()
        }
    }.GetNewClosure())
    $btnPanel.Children.Add($restoreBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "14,6"
    $cancelBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $cancelBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-MaintenanceDialog {
    $result = @{ Cancelled = $true; Profile = "" }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Monthly Maintenance"
    $dlg.Width = 450
    $dlg.Height = 340
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Select Maintenance Type"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,16"
    $stack.Children.Add($title)

    # Radio buttons for maintenance options
    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full Maintenance"
    $radioFull.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioFull.Margin = "0,0,0,4"
    $radioFull.IsChecked = $true
    $stack.Children.Add($radioFull)

    $fullDesc = New-Object System.Windows.Controls.TextBlock
    $fullDesc.Text = "Sync > Cleanup > Ultimate Cleanup > Backup > Export"
    $fullDesc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $fullDesc.FontSize = 11
    $fullDesc.Margin = "20,0,0,12"
    $stack.Children.Add($fullDesc)

    $radioQuick = New-Object System.Windows.Controls.RadioButton
    $radioQuick.Content = "Quick Maintenance"
    $radioQuick.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioQuick.Margin = "0,0,0,4"
    $stack.Children.Add($radioQuick)

    $quickDesc = New-Object System.Windows.Controls.TextBlock
    $quickDesc.Text = "Sync > Cleanup > Backup (skip heavy cleanup)"
    $quickDesc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $quickDesc.FontSize = 11
    $quickDesc.Margin = "20,0,0,12"
    $stack.Children.Add($quickDesc)

    $radioSync = New-Object System.Windows.Controls.RadioButton
    $radioSync.Content = "Sync Only"
    $radioSync.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioSync.Margin = "0,0,0,4"
    $stack.Children.Add($radioSync)

    $syncDesc = New-Object System.Windows.Controls.TextBlock
    $syncDesc.Text = "Synchronize and approve updates only"
    $syncDesc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $syncDesc.FontSize = 11
    $syncDesc.Margin = "20,0,0,20"
    $stack.Children.Add($syncDesc)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $runBtn = New-Object System.Windows.Controls.Button
    $runBtn.Content = "Run Maintenance"
    $runBtn.Padding = "14,6"
    $runBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
    $runBtn.Foreground = "White"
    $runBtn.BorderThickness = 0
    $runBtn.Margin = "0,0,8,0"
    $runBtn.Add_Click({
        $result.Cancelled = $false
        if ($radioFull.IsChecked) { $result.Profile = "Full" }
        elseif ($radioQuick.IsChecked) { $result.Profile = "Quick" }
        else { $result.Profile = "SyncOnly" }
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($runBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "14,6"
    $cancelBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $cancelBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null
    return $result
}

function Show-ScheduleTaskDialog {
    $result = @{
        Cancelled = $true
        Schedule = "Weekly"
        DayOfWeek = "Saturday"
        DayOfMonth = 1
        Time = "02:00"
        Profile = "Full"
        RunAsUser = ".\dod_admin"
        Password = ""
    }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Schedule Monthly Maintenance"
    $dlg.Width = 460
    $dlg.Height = 480
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Create Scheduled Task"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    $note = New-Object System.Windows.Controls.TextBlock
    $note.Text = "Recommended: Weekly on Saturday at 02:00"
    $note.FontSize = 11
    $note.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $note.Margin = "0,0,0,16"
    $stack.Children.Add($note)

    $scheduleLbl = New-Object System.Windows.Controls.TextBlock
    $scheduleLbl.Text = "Schedule:"
    $scheduleLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $scheduleLbl.Margin = "0,0,0,6"
    $stack.Children.Add($scheduleLbl)

    $comboItemStyle = New-Object System.Windows.Style ([System.Windows.Controls.ComboBoxItem])
    $comboItemStyle.Setters.Add((New-Object System.Windows.Setter ([System.Windows.Controls.Control]::BackgroundProperty, ([System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")))))
    $comboItemStyle.Setters.Add((New-Object System.Windows.Setter ([System.Windows.Controls.Control]::ForegroundProperty, ([System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")))))
    $comboItemStyle.Setters.Add((New-Object System.Windows.Setter ([System.Windows.Controls.Control]::PaddingProperty, "6,4")))
    $comboItemStyle.Setters.Add((New-Object System.Windows.Setter ([System.Windows.Controls.Control]::BorderBrushProperty, ([System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")))))
    $comboItemStyle.Setters.Add((New-Object System.Windows.Setter ([System.Windows.Controls.Control]::BorderThicknessProperty, 0)))

    $comboHoverTrigger = New-Object System.Windows.Trigger
    $comboHoverTrigger.Property = [System.Windows.Controls.ComboBoxItem]::IsMouseOverProperty
    $comboHoverTrigger.Value = $true
    $comboHoverTrigger.Setters.Add((New-Object System.Windows.Setter ([System.Windows.Controls.Control]::BackgroundProperty, ([System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")))))
    $comboItemStyle.Triggers.Add($comboHoverTrigger)

    $scheduleCombo = New-Object System.Windows.Controls.ComboBox
    $scheduleCombo.Items.Add("Weekly") | Out-Null
    $scheduleCombo.Items.Add("Monthly") | Out-Null
    $scheduleCombo.Items.Add("Daily") | Out-Null
    $scheduleCombo.SelectedIndex = 0
    $scheduleCombo.Margin = "0,0,0,12"
    $scheduleCombo.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $scheduleCombo.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $scheduleCombo.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
    $scheduleCombo.BorderThickness = "1"
    $scheduleCombo.ItemContainerStyle = $comboItemStyle
    $scheduleCombo.Resources[[System.Windows.SystemColors]::WindowBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $scheduleCombo.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $scheduleCombo.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $stack.Children.Add($scheduleCombo)

    $dayOfWeekPanel = New-Object System.Windows.Controls.StackPanel
    $dayOfWeekPanel.Margin = "0,0,0,12"

    $dowLbl = New-Object System.Windows.Controls.TextBlock
    $dowLbl.Text = "Day of Week:"
    $dowLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $dowLbl.Margin = "0,0,0,6"
    $dayOfWeekPanel.Children.Add($dowLbl)

    $dowCombo = New-Object System.Windows.Controls.ComboBox
    @("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday") | ForEach-Object {
        $dowCombo.Items.Add($_) | Out-Null
    }
    $dowCombo.SelectedItem = "Saturday"
    $dowCombo.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $dowCombo.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $dowCombo.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
    $dowCombo.BorderThickness = "1"
    $dowCombo.ItemContainerStyle = $comboItemStyle
    $dowCombo.Resources[[System.Windows.SystemColors]::WindowBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dowCombo.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $dowCombo.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $dayOfWeekPanel.Children.Add($dowCombo)
    $stack.Children.Add($dayOfWeekPanel)

    $dayOfMonthPanel = New-Object System.Windows.Controls.StackPanel
    $dayOfMonthPanel.Margin = "0,0,0,12"
    $dayOfMonthPanel.Visibility = "Collapsed"

    $domLbl = New-Object System.Windows.Controls.TextBlock
    $domLbl.Text = "Day of Month (1-31):"
    $domLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $domLbl.Margin = "0,0,0,6"
    $dayOfMonthPanel.Children.Add($domLbl)

    $domBox = New-Object System.Windows.Controls.TextBox
    $domBox.Text = "1"
    $domBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $domBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $domBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
    $domBox.BorderThickness = "1"
    $domBox.Padding = "6,4"
    $dayOfMonthPanel.Children.Add($domBox)
    $stack.Children.Add($dayOfMonthPanel)

    $timeLbl = New-Object System.Windows.Controls.TextBlock
    $timeLbl.Text = "Start Time (HH:mm):"
    $timeLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $timeLbl.Margin = "0,0,0,6"
    $stack.Children.Add($timeLbl)

    $timeBox = New-Object System.Windows.Controls.TextBox
    $timeBox.Text = "02:00"
    $timeBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $timeBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $timeBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
    $timeBox.BorderThickness = "1"
    $timeBox.Padding = "6,4"
    $timeBox.Margin = "0,0,0,12"
    $stack.Children.Add($timeBox)

    $profileLbl = New-Object System.Windows.Controls.TextBlock
    $profileLbl.Text = "Maintenance Profile:"
    $profileLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $profileLbl.Margin = "0,0,0,6"
    $stack.Children.Add($profileLbl)

    $profileCombo = New-Object System.Windows.Controls.ComboBox
    @("Full","Quick","SyncOnly") | ForEach-Object { $profileCombo.Items.Add($_) | Out-Null }
    $profileCombo.SelectedItem = "Full"
    $profileCombo.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $profileCombo.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $profileCombo.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
    $profileCombo.BorderThickness = "1"
    $profileCombo.ItemContainerStyle = $comboItemStyle
    $profileCombo.Resources[[System.Windows.SystemColors]::WindowBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $profileCombo.Resources[[System.Windows.SystemColors]::HighlightBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $profileCombo.Resources[[System.Windows.SystemColors]::ControlTextBrushKey] = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $profileCombo.Margin = "0,0,0,12"
    $stack.Children.Add($profileCombo)

    # Credentials section
    $credLbl = New-Object System.Windows.Controls.TextBlock
    $credLbl.Text = "Run As Credentials (for unattended execution):"
    $credLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $credLbl.FontSize = 11
    $credLbl.Margin = "0,4,0,8"
    $stack.Children.Add($credLbl)

    $userLbl = New-Object System.Windows.Controls.TextBlock
    $userLbl.Text = "Username (e.g., .\dod_admin or DOMAIN\user):"
    $userLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $userLbl.Margin = "0,0,0,6"
    $stack.Children.Add($userLbl)

    $userBox = New-Object System.Windows.Controls.TextBox
    $userBox.Text = ".\dod_admin"
    $userBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $userBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $userBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
    $userBox.BorderThickness = "1"
    $userBox.Padding = "6,4"
    $userBox.Margin = "0,0,0,12"
    $stack.Children.Add($userBox)

    $passLbl = New-Object System.Windows.Controls.TextBlock
    $passLbl.Text = "Password:"
    $passLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $passLbl.Margin = "0,0,0,6"
    $stack.Children.Add($passLbl)

    $passBox = New-Object System.Windows.Controls.PasswordBox
    $passBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $passBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $passBox.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#30363D")
    $passBox.BorderThickness = "1"
    $passBox.Padding = "6,4"
    $passBox.Margin = "0,0,0,16"
    $stack.Children.Add($passBox)

    $scheduleCombo.Add_SelectionChanged({
        if (-not $scheduleCombo.SelectedItem) { return }
        $selected = $scheduleCombo.SelectedItem.ToString()
        if ($selected -eq "Monthly") {
            $dayOfWeekPanel.Visibility = "Collapsed"
            $dayOfMonthPanel.Visibility = "Visible"
        } elseif ($selected -eq "Weekly") {
            $dayOfWeekPanel.Visibility = "Visible"
            $dayOfMonthPanel.Visibility = "Collapsed"
        } else {
            $dayOfWeekPanel.Visibility = "Collapsed"
            $dayOfMonthPanel.Visibility = "Collapsed"
        }
    }.GetNewClosure())

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $saveBtn = New-Object System.Windows.Controls.Button
    $saveBtn.Content = "Create Task"
    $saveBtn.Padding = "14,6"
    $saveBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
    $saveBtn.Foreground = "White"
    $saveBtn.BorderThickness = 0
    $saveBtn.Margin = "0,0,8,0"
    $saveBtn.Add_Click({
        $timeValue = $timeBox.Text.Trim()
        if ($timeValue -notmatch '^\d{1,2}:\d{2}$') {
            [System.Windows.MessageBox]::Show("Invalid time format. Use HH:mm (e.g., 02:00).", "Schedule", "OK", "Warning")
            return
        }
        $scheduleValue = $scheduleCombo.SelectedItem.ToString()
        $domValue = 1
        if ($scheduleValue -eq "Monthly") {
            if (-not [int]::TryParse($domBox.Text, [ref]$domValue) -or $domValue -lt 1 -or $domValue -gt 31) {
                [System.Windows.MessageBox]::Show("Day of month must be between 1 and 31.", "Schedule", "OK", "Warning")
                return
            }
        }
        # Validate credentials
        $userName = $userBox.Text.Trim()
        $password = $passBox.Password
        if ([string]::IsNullOrWhiteSpace($userName)) {
            [System.Windows.MessageBox]::Show("Username is required for scheduled task execution.", "Schedule", "OK", "Warning")
            return
        }
        if ([string]::IsNullOrWhiteSpace($password)) {
            [System.Windows.MessageBox]::Show("Password is required for scheduled task execution.`n`nThe task needs credentials to run whether the user is logged on or not.", "Schedule", "OK", "Warning")
            return
        }
        $result.Schedule = $scheduleValue
        $result.DayOfWeek = $dowCombo.SelectedItem.ToString()
        $result.DayOfMonth = $domValue
        $result.Time = $timeValue
        $result.Profile = $profileCombo.SelectedItem.ToString()
        $result.RunAsUser = $userName
        $result.Password = $password
        $result.Cancelled = $false
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($saveBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "14,6"
    $cancelBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $cancelBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $cancelBtn.BorderThickness = 0
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null

    return $result
}

function Show-TransferDialog {
    $result = @{ Cancelled = $true; Direction = ""; Path = ""; SourcePath = ""; DestinationPath = "C:\WSUS"; ExportMode = "Full"; DaysOld = 30 }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Transfer Data"
    $dlg.Width = 500
    $dlg.Height = 450
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Transfer WSUS Data"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,16"
    $stack.Children.Add($title)

    # Direction selection
    $dirLbl = New-Object System.Windows.Controls.TextBlock
    $dirLbl.Text = "Transfer Direction:"
    $dirLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $dirLbl.Margin = "0,0,0,8"
    $stack.Children.Add($dirLbl)

    $radioExport = New-Object System.Windows.Controls.RadioButton
    $radioExport.Content = "Export (Online server to media)"
    $radioExport.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioExport.Margin = "0,0,0,4"
    $radioExport.IsChecked = $true
    $stack.Children.Add($radioExport)

    $radioImport = New-Object System.Windows.Controls.RadioButton
    $radioImport.Content = "Import (Media to air-gapped server)"
    $radioImport.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioImport.Margin = "0,0,0,12"
    $stack.Children.Add($radioImport)

    # Export Mode section (only visible when Export is selected)
    $exportModePanel = New-Object System.Windows.Controls.StackPanel
    $exportModePanel.Margin = "0,0,0,12"

    $modeLbl = New-Object System.Windows.Controls.TextBlock
    $modeLbl.Text = "Export Mode:"
    $modeLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $modeLbl.Margin = "0,0,0,8"
    $exportModePanel.Children.Add($modeLbl)

    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full copy (all files)"
    $radioFull.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioFull.Margin = "0,0,0,4"
    $radioFull.GroupName = "ExportMode"
    $exportModePanel.Children.Add($radioFull)

    $radioDiff30 = New-Object System.Windows.Controls.RadioButton
    $radioDiff30.Content = "Differential (files from last 30 days)"
    $radioDiff30.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioDiff30.Margin = "0,0,0,4"
    $radioDiff30.GroupName = "ExportMode"
    $radioDiff30.IsChecked = $true
    $exportModePanel.Children.Add($radioDiff30)

    $diffCustomPanel = New-Object System.Windows.Controls.StackPanel
    $diffCustomPanel.Orientation = "Horizontal"
    $diffCustomPanel.Margin = "0,0,0,4"

    $radioDiffCustom = New-Object System.Windows.Controls.RadioButton
    $radioDiffCustom.Content = "Differential (custom days):"
    $radioDiffCustom.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $radioDiffCustom.GroupName = "ExportMode"
    $radioDiffCustom.Margin = "0,0,8,0"
    $diffCustomPanel.Children.Add($radioDiffCustom)

    $txtDays = New-Object System.Windows.Controls.TextBox
    $txtDays.Text = "30"
    $txtDays.Width = 50
    $txtDays.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $txtDays.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $txtDays.Padding = "4,2"
    $diffCustomPanel.Children.Add($txtDays)

    $exportModePanel.Children.Add($diffCustomPanel)
    $stack.Children.Add($exportModePanel)

    # Show/hide panels based on direction
    $radioExport.Add_Checked({
        $exportModePanel.Visibility = "Visible"
        $importDestPanel.Visibility = "Collapsed"
        $pathLbl.Text = "Destination folder:"
    }.GetNewClosure())
    $radioImport.Add_Checked({
        $exportModePanel.Visibility = "Collapsed"
        $importDestPanel.Visibility = "Visible"
        $pathLbl.Text = "Source folder (external media):"
    }.GetNewClosure())

    # Auto-select mode based on detected server mode
    if ($script:ServerMode -eq "Air-Gap") {
        $radioExport.IsEnabled = $false
        $radioImport.IsChecked = $true
        $exportModePanel.Visibility = "Collapsed"
        $importDestPanel.Visibility = "Visible"
        $pathLbl.Text = "Source folder (external media):"
    }

    # Path selection - Export destination / Import source
    $pathLbl = New-Object System.Windows.Controls.TextBlock
    $pathLbl.Text = "Destination folder:"
    $pathLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $pathLbl.Margin = "0,0,0,6"
    $stack.Children.Add($pathLbl)

    $pathPanel = New-Object System.Windows.Controls.DockPanel
    $pathPanel.Margin = "0,0,0,12"

    $browseBtn = New-Object System.Windows.Controls.Button
    $browseBtn.Content = "Browse"
    $browseBtn.Padding = "10,4"
    $browseBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $browseBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $browseBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($browseBtn, "Right")
    $pathPanel.Children.Add($browseBtn)

    $pathTxt = New-Object System.Windows.Controls.TextBox
    $pathTxt.Margin = "0,0,8,0"
    $pathTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $pathTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $pathTxt.Padding = "6,4"
    $pathPanel.Children.Add($pathTxt)

    $browseBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = if ($radioExport.IsChecked) { "Select destination folder for export" } else { "Select source folder (external media)" }
        if ($fbd.ShowDialog() -eq "OK") { $pathTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())
    $stack.Children.Add($pathPanel)

    # Import destination panel (only visible when Import is selected)
    $importDestPanel = New-Object System.Windows.Controls.StackPanel
    $importDestPanel.Visibility = "Collapsed"
    $importDestPanel.Margin = "0,0,0,12"

    $importDestLbl = New-Object System.Windows.Controls.TextBlock
    $importDestLbl.Text = "WSUS destination folder:"
    $importDestLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $importDestLbl.Margin = "0,0,0,6"
    $importDestPanel.Children.Add($importDestLbl)

    $importDestDock = New-Object System.Windows.Controls.DockPanel

    $importDestBtn = New-Object System.Windows.Controls.Button
    $importDestBtn.Content = "Browse"
    $importDestBtn.Padding = "10,4"
    $importDestBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $importDestBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $importDestBtn.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($importDestBtn, "Right")
    $importDestDock.Children.Add($importDestBtn)

    $importDestTxt = New-Object System.Windows.Controls.TextBox
    $importDestTxt.Text = "C:\WSUS"
    $importDestTxt.Margin = "0,0,8,0"
    $importDestTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $importDestTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $importDestTxt.Padding = "6,4"
    $importDestDock.Children.Add($importDestTxt)

    $importDestBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select WSUS destination folder"
        $fbd.SelectedPath = $importDestTxt.Text
        if ($fbd.ShowDialog() -eq "OK") { $importDestTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())
    $importDestPanel.Children.Add($importDestDock)
    $stack.Children.Add($importDestPanel)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $runBtn = New-Object System.Windows.Controls.Button
    $runBtn.Content = "Start Transfer"
    $runBtn.Padding = "14,6"
    $runBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
    $runBtn.Foreground = "White"
    $runBtn.BorderThickness = 0
    $runBtn.Margin = "0,0,8,0"
    $runBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($pathTxt.Text)) {
            $msg = if ($radioExport.IsChecked) { "Select destination folder." } else { "Select source folder." }
            [System.Windows.MessageBox]::Show($msg, "Transfer", "OK", "Warning")
            return
        }
        # Validate import destination
        if ($radioImport.IsChecked -and [string]::IsNullOrWhiteSpace($importDestTxt.Text)) {
            [System.Windows.MessageBox]::Show("Select WSUS destination folder.", "Transfer", "OK", "Warning")
            return
        }
        $result.Cancelled = $false
        $result.Direction = if ($radioExport.IsChecked) { "Export" } else { "Import" }
        $result.Path = $pathTxt.Text
        # For Import, also set SourcePath and DestinationPath
        if ($radioImport.IsChecked) {
            $result.SourcePath = $pathTxt.Text
            $result.DestinationPath = $importDestTxt.Text
        }
        # Determine export mode
        if ($radioFull.IsChecked) {
            $result.ExportMode = "Full"
            $result.DaysOld = 0
        } elseif ($radioDiff30.IsChecked) {
            $result.ExportMode = "Differential"
            $result.DaysOld = 30
        } else {
            $result.ExportMode = "Differential"
            $daysVal = 30
            if ([int]::TryParse($txtDays.Text, [ref]$daysVal) -and $daysVal -gt 0) {
                $result.DaysOld = $daysVal
            } else {
                $result.DaysOld = 30
            }
        }
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($runBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "14,6"
    $cancelBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $cancelBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
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
    $dlg.Title = "Settings"
    $dlg.Width = 400
    $dlg.Height = 220
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $script:window
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
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
    $lbl1.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $lbl1.Margin = "0,0,0,4"
    $stack.Children.Add($lbl1)

    $txt1 = New-Object System.Windows.Controls.TextBox
    $txt1.Text = $script:ContentPath
    $txt1.Margin = "0,0,0,12"
    $txt1.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $txt1.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $txt1.Padding = "6,4"
    $stack.Children.Add($txt1)

    $lbl2 = New-Object System.Windows.Controls.TextBlock
    $lbl2.Text = "SQL Instance:"
    $lbl2.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $lbl2.Margin = "0,0,0,4"
    $stack.Children.Add($lbl2)

    $txt2 = New-Object System.Windows.Controls.TextBox
    $txt2.Text = $script:SqlInstance
    $txt2.Margin = "0,0,0,16"
    $txt2.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $txt2.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $txt2.Padding = "6,4"
    $stack.Children.Add($txt2)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $saveBtn = New-Object System.Windows.Controls.Button
    $saveBtn.Content = "Save"
    $saveBtn.Padding = "14,6"
    $saveBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
    $saveBtn.Foreground = "White"
    $saveBtn.BorderThickness = 0
    $saveBtn.Margin = "0,0,8,0"
    $saveBtn.Add_Click({
        $script:ContentPath = if($txt1.Text){$txt1.Text}else{"C:\WSUS"}
        $script:SqlInstance = if($txt2.Text){$txt2.Text}else{".\SQLEXPRESS"}
        Save-Settings
        Update-Dashboard
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($saveBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Padding = "14,6"
    $cancelBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $cancelBtn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
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
        [System.Windows.MessageBox]::Show("An operation is already running. Please wait for it to complete or cancel it.", "Operation In Progress", "OK", "Warning")
        return
    }

    # Guard Online-only operations
    if ($script:ServerMode -eq "Air-Gap" -and $Id -in @("maintenance", "schedule")) {
        [System.Windows.MessageBox]::Show("This operation is only available on the Online WSUS server.", "Online Only", "OK", "Warning")
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
            [System.Windows.MessageBox]::Show("Cannot find Invoke-WsusManagement.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe", "Script Not Found", "OK", "Error")
            Write-Log "ERROR: Invoke-WsusManagement.ps1 not found in $sr or $sr\Scripts"
            return
        }
        if ($Id -eq "maintenance" -and -not $maint) {
            [System.Windows.MessageBox]::Show("Cannot find Invoke-WsusMonthlyMaintenance.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe", "Script Not Found", "OK", "Error")
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
                [System.Windows.MessageBox]::Show("Cannot find Install-WsusWithSqlExpress.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe", "Script Not Found", "OK", "Error")
                Write-Log "ERROR: Install-WsusWithSqlExpress.ps1 not found"
                return
            }

            $installerPath = if ($controls.InstallPathBox) { $controls.InstallPathBox.Text } else { $script:InstallPath }
            $installerPath = $installerPath.Trim()
            if (-not (Test-SafePath $installerPath)) {
                [System.Windows.MessageBox]::Show("Invalid installer path. Please select a valid folder.", "Error", "OK", "Error")
                return
            }
            if (-not (Test-Path $installerPath)) {
                [System.Windows.MessageBox]::Show("Installer folder not found: $installerPath", "Error", "OK", "Error")
                return
            }
            $sqlInstaller = Join-Path $installerPath "SQLEXPRADV_x64_ENU.exe"
            if (-not (Test-Path $sqlInstaller)) {
                [System.Windows.MessageBox]::Show("SQLEXPRADV_x64_ENU.exe not found in $installerPath.`n`nPlease select the folder containing the SQL Server installation files.", "Error", "OK", "Error")
                return
            }
            $script:InstallPath = $installerPath

            $saPassword = if ($controls.InstallSaPassword) { $controls.InstallSaPassword.Password } else { "" }
            if ([string]::IsNullOrWhiteSpace($saPassword)) {
                [System.Windows.MessageBox]::Show("SA password is required.", "Error", "OK", "Error")
                return
            }
            $saPasswordConfirm = if ($controls.InstallSaPasswordConfirm) { $controls.InstallSaPasswordConfirm.Password } else { "" }
            if ([string]::IsNullOrWhiteSpace($saPasswordConfirm)) {
                [System.Windows.MessageBox]::Show("SA password confirmation is required.", "Error", "OK", "Error")
                return
            }
            if ($saPassword -ne $saPasswordConfirm) {
                [System.Windows.MessageBox]::Show("SA passwords do not match.", "Error", "OK", "Error")
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
                [System.Windows.MessageBox]::Show("Invalid backup path.", "Error", "OK", "Error")
                return
            }
            $bkp = Get-EscapedPath $opts.BackupPath
            "& '$mgmtSafe' -Restore -ContentPath '$cp' -SqlInstance '$sql' -BackupPath '$bkp'"
        }
        "transfer" {
            $opts = Show-TransferDialog
            if ($opts.Cancelled) { return }
            if (-not (Test-SafePath $opts.Path)) {
                [System.Windows.MessageBox]::Show("Invalid path.", "Error", "OK", "Error")
                return
            }
            $path = Get-EscapedPath $opts.Path
            if ($opts.Direction -eq "Export") {
                # Build title with export mode info
                $modeDesc = if ($opts.ExportMode -eq "Full") { "Full" } else { "Differential, $($opts.DaysOld) days" }
                $Title = "Export ($modeDesc)"
                "& '$mgmtSafe' -Export -ContentPath '$cp' -DestinationPath '$path' -CopyMode '$($opts.ExportMode)' -DaysOld $($opts.DaysOld)"
            } else {
                # Import - validate destination path too
                if (-not (Test-SafePath $opts.DestinationPath)) {
                    [System.Windows.MessageBox]::Show("Invalid destination path.", "Error", "OK", "Error")
                    return
                }
                $srcPath = Get-EscapedPath $opts.SourcePath
                $destPath = Get-EscapedPath $opts.DestinationPath
                $Title = "Import"
                "& '$mgmtSafe' -Import -ContentPath '$cp' -SourcePath '$srcPath' -DestinationPath '$destPath' -NonInteractive"
            }
        }
        "maintenance" {
            $opts = Show-MaintenanceDialog
            if ($opts.Cancelled) { return }
            $Title = "$Title ($($opts.Profile))"
            "& '$maintSafe' -Unattended -MaintenanceProfile '$($opts.Profile)' -NoTranscript -UseWindowsAuth"
        }
        "schedule" {
            $opts = Show-ScheduleTaskDialog
            if ($opts.Cancelled) { return }
            if (-not $taskModuleSafe) {
                [System.Windows.MessageBox]::Show("Cannot find WsusScheduledTask.psm1`n`nSearched in:`n- $sr\Modules`n- $(Split-Path $sr -Parent)\Modules`n`nMake sure the Modules folder is in the same directory as WsusManager.exe", "Module Not Found", "OK", "Error")
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
            "& { Import-Module '$taskModuleSafe' -Force -DisableNameChecking; `$secPwd = ConvertTo-SecureString `$env:WSUS_TASK_PASSWORD -AsPlainText -Force; New-WsusMaintenanceTask $args -UserPassword `$secPwd; Remove-Item Env:\WSUS_TASK_PASSWORD -ErrorAction SilentlyContinue }"
        }
        "cleanup"     { "& '$mgmtSafe' -Cleanup -Force -SqlInstance '$sql'" }
        "health"      { "`$null = & '$mgmtSafe' -Health -ContentPath '$cp' -SqlInstance '$sql'" }
        "repair"      { "`$null = & '$mgmtSafe' -Repair -ContentPath '$cp' -SqlInstance '$sql'" }
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
            # Set smaller console window with more columns (smaller text appearance)
            $setupConsole = "mode con: cols=120 lines=18; `$Host.UI.RawUI.WindowTitle = 'WSUS Manager - $Title'"
            $wrappedCmd = "$setupConsole; $cmd; Write-Host ''; Write-Host '=== Operation Complete ===' -ForegroundColor Green; Write-Host 'Press any key to close this window...'; `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')"
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
            }

            $script:ExitEventJob = Register-ObjectEvent -InputObject $script:CurrentProcess -EventName Exited -Action $exitHandler -MessageData $eventData

            $script:CurrentProcess.Start() | Out-Null

            # Give the process a moment to create its window
            Start-Sleep -Milliseconds 500

            # Position and resize the console window to match log panel area
            try {
                $hWnd = $script:CurrentProcess.MainWindowHandle
                if ($hWnd -ne [IntPtr]::Zero) {
                    # Get main window position
                    $mainLeft = [int]$script:window.Left
                    $mainTop = [int]$script:window.Top
                    $mainWidth = [int]$script:window.ActualWidth
                    $mainHeight = [int]$script:window.ActualHeight

                    # Position console in log panel area (right side of app, above bottom)
                    # Sidebar is ~180px, content area starts at ~200px
                    $screenWidth = [System.Windows.SystemParameters]::VirtualScreenWidth
                    $screenHeight = [System.Windows.SystemParameters]::VirtualScreenHeight

                    $consoleHeight = 220  # Slightly smaller than log panel
                    # Position at sidebar offset, constrained to app width
                    $consoleX = [math]::Max(0, $mainLeft + 195)
                    $consoleY = [math]::Max(0, $mainTop + $mainHeight - 255)  # Near bottom
                    # Width = app width minus sidebar minus margins (keep within app boundary)
                    $consoleWidth = [math]::Min(($mainWidth - 215), ($mainLeft + $mainWidth - $consoleX - 15))
                    $consoleWidth = [math]::Max(350, $consoleWidth)  # Min 350px

                    # Apply screen bounds
                    $consoleX = [math]::Min($consoleX, $screenWidth - $consoleWidth - 10)
                    $consoleY = [math]::Min($consoleY, $screenHeight - $consoleHeight - 40)

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
                    $data.Controls.LogOutput.AppendText("[$timestamp] [+] $($data.Title) completed`r`n")
                    $data.Controls.LogOutput.ScrollToEnd()
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
        [System.Windows.MessageBox]::Show("DomainController folder not found.`n`nExpected locations:`n- $sr\DomainController`n- $sr\Scripts\DomainController", "Error", "OK", "Error")
        return
    }

    $destDir = "C:\WSUS GPO"

    # Confirm dialog
    $result = [System.Windows.MessageBox]::Show(
        "This will copy GPO files to:`n$destDir`n`nContinue?",
        "Create GPO Files", "YesNo", "Question")

    if ($result -ne "Yes") { return }

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

1. Copy 'C:\WSUS GPO' folder to the Domain Controller

2. On the DC, run as Administrator:
   cd 'C:\WSUS GPO'
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
        [System.Windows.MessageBox]::Show(
            "GPO files created at: $destDir`n`nNext steps:`n1. Copy folder to Domain Controller`n2. Run Set-WsusGroupPolicy.ps1 as Admin`n3. Run 'gpupdate /force' on clients`n`nSee log panel for full commands.",
            "GPO Files Created", "OK", "Information")

    } catch {
        Write-LogOutput "Error: $_" -Level Error
        [System.Windows.MessageBox]::Show("Failed to create GPO files: $_", "Error", "OK", "Error")
    } finally {
        # Re-enable buttons (respects WSUS installation status)
        Enable-OperationButtons
    }
})
$controls.BtnTransfer.Add_Click({ Invoke-LogOperation "transfer" "Transfer" })
$controls.BtnMaintenance.Add_Click({ Invoke-LogOperation "maintenance" "Monthly Maintenance" })
$controls.BtnSchedule.Add_Click({ Invoke-LogOperation "schedule" "Schedule Task" })
$controls.BtnCleanup.Add_Click({ Invoke-LogOperation "cleanup" "Deep Cleanup" })
$controls.BtnHealth.Add_Click({ Invoke-LogOperation "health" "Health Check" })
$controls.BtnRepair.Add_Click({ Invoke-LogOperation "repair" "Repair" })
$controls.BtnAbout.Add_Click({ Show-Panel "About" "About" "BtnAbout" })
$controls.BtnHelp.Add_Click({ Show-Help "Overview" })
$controls.BtnSettings.Add_Click({ Show-SettingsDialog })

$controls.BtnBrowseInstallPath.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Select folder containing SQL Server installers (SQLEXPRADV_x64_ENU.exe, SSMS-Setup-ENU.exe)"
    $fbd.SelectedPath = $script:InstallPath
    if ($fbd.ShowDialog() -eq "OK") {
        $p = $fbd.SelectedPath
        if (-not (Test-SafePath $p)) {
            [System.Windows.MessageBox]::Show("Invalid path.", "Error", "OK", "Error")
            return
        }
        $controls.InstallPathBox.Text = $p
        $script:InstallPath = $p
    }
})

$controls.BtnRunInstall.Add_Click({ Invoke-LogOperation "install" "Install WSUS" })

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

$controls.QBtnHealth.Add_Click({ Invoke-LogOperation "health" "Health Check" })
$controls.QBtnCleanup.Add_Click({ Invoke-LogOperation "cleanup" "Deep Cleanup" })
$controls.QBtnMaint.Add_Click({ Invoke-LogOperation "maintenance" "Monthly Maintenance" })
$controls.QBtnStart.Add_Click({
    $controls.QBtnStart.IsEnabled = $false
    $controls.QBtnStart.Content = "Starting..."
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
    Update-Dashboard
    Write-LogOutput "Service startup complete" -Level Success
    Set-Status "Ready"
    $controls.QBtnStart.Content = "Start Services"
    $controls.QBtnStart.IsEnabled = $true
})

$controls.BtnOpenLog.Add_Click({
    if (Test-Path $script:LogDir) { Start-Process explorer.exe -ArgumentList $script:LogDir }
    else { [System.Windows.MessageBox]::Show("Log folder not found.", "Log", "OK", "Warning") }
})

# Log panel buttons
$controls.BtnLiveTerminal.Add_Click({
    $script:LiveTerminalMode = -not $script:LiveTerminalMode
    if ($script:LiveTerminalMode) {
        $controls.BtnLiveTerminal.Content = "Live Terminal: On"
        $controls.BtnLiveTerminal.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#238636")
        $controls.LogOutput.Text = "Live Terminal Mode enabled.`r`n`r`nOperations will open in a separate PowerShell console window.`r`nYou can interact with the terminal, scroll, and see live output.`r`n`r`nClick 'Live Terminal: On' to switch back to embedded log mode."
    } else {
        $controls.BtnLiveTerminal.Content = "Live Terminal: Off"
        $controls.BtnLiveTerminal.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
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

$controls.BtnBack.Add_Click({ Show-Panel "Dashboard" "Dashboard" "BtnDashboard" })
$controls.BtnCancel.Add_Click({
    Stop-CurrentOperation
    Enable-OperationButtons
    $controls.BtnCancel.Visibility = "Collapsed"
    Set-Status "Cancelled"
})
#endregion

#region Initialize
$controls.VersionLabel.Text = "v$script:AppVersion"
$controls.AboutVersion.Text = "Version $script:AppVersion"

# Initialize Live Terminal button state from saved settings
if ($script:LiveTerminalMode) {
    $controls.BtnLiveTerminal.Content = "Live Terminal: On"
    $controls.BtnLiveTerminal.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#238636")
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

Update-Dashboard

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
    if ($controls.DashboardPanel.Visibility -eq "Visible" -and -not $script:RefreshInProgress) {
        $script:RefreshInProgress = $true
        try { Update-Dashboard } finally { $script:RefreshInProgress = $false }
    }
})
$timer.Start()

$script:window.Add_Closing({
    $timer.Stop()
    # Clean up any running operation (suppress log since we're closing)
    Stop-CurrentOperation -SuppressLog
})
#endregion

#region Main Entry Point with Error Handling
$script:StartupDuration = ((Get-Date) - $script:StartupTime).TotalMilliseconds
Write-Log "Startup completed in $([math]::Round($script:StartupDuration, 0))ms"
Write-Log "Running WPF form"

try {
    $script:window.ShowDialog() | Out-Null
}
catch {
    $errorMsg = "A fatal error occurred:`n`n$($_.Exception.Message)"
    Write-Log "FATAL: $($_.Exception.Message)"
    Write-Log "Stack: $($_.ScriptStackTrace)"

    try {
        [System.Windows.MessageBox]::Show(
            $errorMsg,
            "WSUS Manager - Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    catch {
        # If WPF message box fails, try Windows Forms
        [System.Windows.Forms.MessageBox]::Show(
            $errorMsg,
            "WSUS Manager - Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
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

#Requires -Version 5.1
<#
===============================================================================
Script: WsusManagementGui.ps1
Author: Tony Tran, ISSO, Classified Computing, GA-ASI
Version: 3.8.0
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

$script:AppVersion = "3.8.3"
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
$script:LogPath = Join-Path $script:LogDir "WsusGui_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:SettingsFile = Join-Path $env:APPDATA "WsusManager\settings.json"
$script:ContentPath = "C:\WSUS"
$script:SqlInstance = ".\SQLEXPRESS"
$script:ExportRoot = "C:\"
$script:ServerMode = "Online"
$script:RefreshInProgress = $false
$script:CurrentProcess = $null
$script:OperationRunning = $false

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
        }
    } catch { Write-Log "Failed to load settings: $_" }
}

function Save-Settings {
    try {
        $dir = Split-Path $script:SettingsFile -Parent
        if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        @{ ContentPath=$script:ContentPath; SqlInstance=$script:SqlInstance; ExportRoot=$script:ExportRoot; ServerMode=$script:ServerMode } |
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
    if ($Path -notmatch '^[A-Za-z]:\\') { return $false }
    return $true
}

$script:IsAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    $script:IsAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { Write-Log "Admin check failed: $_" }
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

                        <TextBlock Text="TRANSFER" FontSize="9" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,14,0,4"/>
                        <Button x:Name="BtnTransfer" Content="⇄ Export/Import" Style="{StaticResource NavBtn}"/>

                        <TextBlock Text="MAINTENANCE" FontSize="9" FontWeight="Bold" Foreground="{StaticResource Blue}" Margin="16,14,0,4"/>
                        <Button x:Name="BtnMaintenance" Content="📅 Monthly" Style="{StaticResource NavBtn}"/>
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
                    <TextBlock x:Name="AdminBadge" Text="Admin" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource Green}"/>
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
$window = [Windows.Markup.XamlReader]::Load($reader)

$controls = @{}
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    if ($_.Name) { $controls[$_.Name] = $window.FindName($_.Name) }
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

function Update-Dashboard {
    $svc = Get-ServiceStatus
    $controls.Card1Value.Text = if($svc.Running -eq 3){"All Running"}else{"$($svc.Running)/3"}
    $controls.Card1Sub.Text = if($svc.Names.Count -gt 0){$svc.Names -join ", "}else{"Stopped"}
    $controls.Card1Bar.Background = if($svc.Running -eq 3){"#3FB950"}elseif($svc.Running -gt 0){"#D29922"}else{"#F85149"}

    $db = Get-DatabaseSizeGB
    if ($db -ge 0) {
        $controls.Card2Value.Text = "$db / 10 GB"
        $controls.Card2Sub.Text = if($db -ge 9){"Critical!"}elseif($db -ge 7){"Warning"}else{"Healthy"}
        $controls.Card2Bar.Background = if($db -ge 9){"#F85149"}elseif($db -ge 7){"#D29922"}else{"#3FB950"}
    } else {
        $controls.Card2Value.Text = "Offline"
        $controls.Card2Sub.Text = "SQL stopped"
        $controls.Card2Bar.Background = "#D29922"
    }

    $disk = Get-DiskFreeGB
    $controls.Card3Value.Text = "$disk GB"
    $controls.Card3Sub.Text = if($disk -lt 10){"Critical!"}elseif($disk -lt 50){"Low"}else{"OK"}
    $controls.Card3Bar.Background = if($disk -lt 10){"#F85149"}elseif($disk -lt 50){"#D29922"}else{"#3FB950"}

    $task = Get-TaskStatus
    $controls.Card4Value.Text = $task
    $controls.Card4Bar.Background = if($task -eq "Ready"){"#3FB950"}else{"#D29922"}

    $controls.CfgContentPath.Text = $script:ContentPath
    $controls.CfgSqlInstance.Text = $script:SqlInstance
    $controls.CfgExportRoot.Text = $script:ExportRoot
    $controls.CfgLogPath.Text = $script:LogDir
    $controls.StatusLabel.Text = "Updated $(Get-Date -Format 'HH:mm:ss')"
}

function Set-ActiveNavButton {
    param([string]$Active)
    $navBtns = @("BtnDashboard","BtnInstall","BtnRestore","BtnTransfer","BtnMaintenance","BtnCleanup","BtnHealth","BtnRepair","BtnAbout","BtnHelp")
    foreach ($b in $navBtns) {
        if ($controls[$b]) {
            $controls[$b].Background = if($b -eq $Active){"#21262D"}else{"Transparent"}
            $controls[$b].Foreground = if($b -eq $Active){"#E6EDF3"}else{"#8B949E"}
        }
    }
}

# Operation buttons that should be disabled during operations
$script:OperationButtons = @("BtnInstall","BtnRestore","BtnTransfer","BtnMaintenance","BtnCleanup","BtnHealth","BtnRepair","QBtnHealth","QBtnCleanup","QBtnMaint","QBtnStart")

function Disable-OperationButtons {
    foreach ($b in $script:OperationButtons) {
        if ($controls[$b]) {
            $controls[$b].IsEnabled = $false
            $controls[$b].Opacity = 0.5
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
}

function Show-Panel {
    param([string]$Panel, [string]$Title, [string]$NavBtn)
    $controls.PageTitle.Text = $Title
    $controls.DashboardPanel.Visibility = if($Panel -eq "Dashboard"){"Visible"}else{"Collapsed"}
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
4. Toggle Mode for Online/Air-Gap operations

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
• Monthly - Sync, decline superseded, cleanup, backup
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
    $dlg.Owner = $window
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
    $result = @{ Cancelled = $true; SourcePath = "" }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Import from Media"
    $dlg.Width = 450
    $dlg.Height = 220
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $window
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

    $srcLbl = New-Object System.Windows.Controls.TextBlock
    $srcLbl.Text = "Source folder:"
    $srcLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $srcLbl.Margin = "0,0,0,6"
    $stack.Children.Add($srcLbl)

    $srcPanel = New-Object System.Windows.Controls.DockPanel
    $srcPanel.Margin = "0,0,0,20"

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
        if ($fbd.ShowDialog() -eq "OK") { $srcTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())
    $stack.Children.Add($srcPanel)

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
        $result.Cancelled = $false
        $result.SourcePath = $srcTxt.Text
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
    $dlg.Owner = $window
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
    $dlg.Owner = $window
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

function Show-TransferDialog {
    $result = @{ Cancelled = $true; Direction = ""; Path = ""; ExportMode = "Full"; DaysOld = 30 }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Transfer Data"
    $dlg.Width = 500
    $dlg.Height = 380
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $window
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

    # Show/hide export mode based on direction
    $radioExport.Add_Checked({ $exportModePanel.Visibility = "Visible" }.GetNewClosure())
    $radioImport.Add_Checked({ $exportModePanel.Visibility = "Collapsed" }.GetNewClosure())

    # Path selection
    $pathLbl = New-Object System.Windows.Controls.TextBlock
    $pathLbl.Text = "Folder path:"
    $pathLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $pathLbl.Margin = "0,0,0,6"
    $stack.Children.Add($pathLbl)

    $pathPanel = New-Object System.Windows.Controls.DockPanel
    $pathPanel.Margin = "0,0,0,16"

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
        $fbd.Description = if ($radioExport.IsChecked) { "Select destination folder for export" } else { "Select source folder for import" }
        if ($fbd.ShowDialog() -eq "OK") { $pathTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())
    $stack.Children.Add($pathPanel)

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
            [System.Windows.MessageBox]::Show("Select a folder path.", "Transfer", "OK", "Warning")
            return
        }
        $result.Cancelled = $false
        $result.Direction = if ($radioExport.IsChecked) { "Export" } else { "Import" }
        $result.Path = $pathTxt.Text
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
    $dlg.Owner = $window
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

    # Validate scripts exist before proceeding
    if (-not $mgmt) {
        [System.Windows.MessageBox]::Show("Cannot find Invoke-WsusManagement.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe", "Script Not Found", "OK", "Error")
        Write-Log "ERROR: Invoke-WsusManagement.ps1 not found in $sr or $sr\Scripts"
        return
    }
    if (-not $maint) {
        [System.Windows.MessageBox]::Show("Cannot find Invoke-WsusMonthlyMaintenance.ps1`n`nSearched in:`n- $sr`n- $sr\Scripts`n`nMake sure the Scripts folder is in the same directory as WsusManager.exe", "Script Not Found", "OK", "Error")
        Write-Log "ERROR: Invoke-WsusMonthlyMaintenance.ps1 not found in $sr or $sr\Scripts"
        return
    }

    $cp = Get-EscapedPath $script:ContentPath
    $sql = Get-EscapedPath $script:SqlInstance
    $mgmtSafe = Get-EscapedPath $mgmt
    $maintSafe = Get-EscapedPath $maint

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

            # Default installer path
            $defaultInstallerPath = "C:\WSUS\SQLDB"
            $installerPath = $null

            # Check if default path exists
            if (Test-Path $defaultInstallerPath) {
                # Verify it has the required files
                $sqlInstaller = Join-Path $defaultInstallerPath "SQLEXPRADV_x64_ENU.exe"
                if (Test-Path $sqlInstaller) {
                    $installerPath = $defaultInstallerPath
                } else {
                    $result = [System.Windows.MessageBox]::Show("Default installer folder exists ($defaultInstallerPath) but SQLEXPRADV_x64_ENU.exe was not found.`n`nWould you like to browse for a different folder?", "Installer Not Found", "YesNo", "Question")
                    if ($result -ne "Yes") { return }
                }
            }

            # If no valid path yet, prompt user to browse
            if (-not $installerPath) {
                $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
                $fbd.Description = "Select folder containing SQL Server installers (SQLEXPRADV_x64_ENU.exe, SSMS-Setup-ENU.exe)"
                $fbd.SelectedPath = "C:\WSUS"
                if ($fbd.ShowDialog() -eq "OK") {
                    $p = $fbd.SelectedPath
                    if (-not (Test-SafePath $p)) {
                        [System.Windows.MessageBox]::Show("Invalid path.", "Error", "OK", "Error")
                        return
                    }
                    $sqlInstaller = Join-Path $p "SQLEXPRADV_x64_ENU.exe"
                    if (-not (Test-Path $sqlInstaller)) {
                        [System.Windows.MessageBox]::Show("SQLEXPRADV_x64_ENU.exe not found in selected folder.`n`nPlease select the folder containing the SQL Server installation files.", "Error", "OK", "Error")
                        return
                    }
                    $installerPath = $p
                } else { return }
            }

            $installScriptSafe = Get-EscapedPath $installScript
            $installerPathSafe = Get-EscapedPath $installerPath
            "& '$installScriptSafe' -InstallerPath '$installerPathSafe'"
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
                $Title = "Import"
                "& '$mgmtSafe' -Import -ContentPath '$cp' -ExportRoot '$path'"
            }
        }
        "maintenance" {
            $opts = Show-MaintenanceDialog
            if ($opts.Cancelled) { return }
            $Title = "$Title ($($opts.Profile))"
            "& '$maintSafe' -Unattended -MaintenanceProfile '$($opts.Profile)'"
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

    Write-LogOutput "Starting $Title..." -Level Info
    Set-Status "Running: $Title"

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $sr

        $script:CurrentProcess = New-Object System.Diagnostics.Process
        $script:CurrentProcess.StartInfo = $psi
        $script:CurrentProcess.EnableRaisingEvents = $true

        # Create shared state object that can be modified from event handlers
        $eventData = @{
            Window = $window
            Controls = $controls
            Title = $Title
            OperationButtons = $script:OperationButtons
        }

        $outputHandler = {
            $line = $Event.SourceEventArgs.Data
            if ($line) {
                $data = $Event.MessageData
                $level = if($line -match 'ERROR|FAIL'){'Error'}elseif($line -match 'WARN'){'Warning'}elseif($line -match 'OK|Success|\[PASS\]|\[\+\]'){'Success'}else{'Info'}
                $data.Window.Dispatcher.Invoke([Action]{
                    $timestamp = Get-Date -Format "HH:mm:ss"
                    $prefix = switch ($level) { 'Success' { "[+]" } 'Warning' { "[!]" } 'Error' { "[-]" } default { "[*]" } }
                    $data.Controls.LogOutput.AppendText("[$timestamp] $prefix $line`r`n")
                    $data.Controls.LogOutput.ScrollToEnd()
                })
            }
        }

        $exitHandler = {
            $data = $Event.MessageData
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
            })
            # Reset the operation running flag (script scope accessible from event handler)
            $script:OperationRunning = $false
        }

        Register-ObjectEvent -InputObject $script:CurrentProcess -EventName OutputDataReceived -Action $outputHandler -MessageData $eventData | Out-Null
        Register-ObjectEvent -InputObject $script:CurrentProcess -EventName ErrorDataReceived -Action $outputHandler -MessageData $eventData | Out-Null
        Register-ObjectEvent -InputObject $script:CurrentProcess -EventName Exited -Action $exitHandler -MessageData $eventData | Out-Null

        $script:CurrentProcess.Start() | Out-Null
        $script:CurrentProcess.BeginOutputReadLine()
        $script:CurrentProcess.BeginErrorReadLine()

        # Use a timer as backup to check process status and force UI refresh
        # Note: Primary reset happens in exitHandler, timer is backup for edge cases
        $script:OpCheckTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:OpCheckTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:OpCheckTimer.Add_Tick({
            # Force UI to process pending events (keeps log responsive)
            [System.Windows.Forms.Application]::DoEvents()

            if ($null -eq $script:CurrentProcess -or $script:CurrentProcess.HasExited) {
                $script:OperationRunning = $false
                Enable-OperationButtons
                $controls.BtnCancelOp.Visibility = "Collapsed"
                $controls.StatusLabel.Text = " - Ready"
                $this.Stop()
            }
        })
        $script:OpCheckTimer.Start()
    } catch {
        Write-LogOutput "ERROR: $_" -Level Error
        Set-Status "Ready"
        $script:OperationRunning = $false
        Enable-OperationButtons
        $controls.BtnCancelOp.Visibility = "Collapsed"
    }
}

#endregion

#region Event Handlers
$controls.BtnDashboard.Add_Click({ Show-Panel "Dashboard" "Dashboard" "BtnDashboard" })
$controls.BtnInstall.Add_Click({ Invoke-LogOperation "install" "Install WSUS" })
$controls.BtnRestore.Add_Click({ Invoke-LogOperation "restore" "Restore Database" })
$controls.BtnTransfer.Add_Click({ Invoke-LogOperation "transfer" "Transfer" })
$controls.BtnMaintenance.Add_Click({ Invoke-LogOperation "maintenance" "Monthly Maintenance" })
$controls.BtnCleanup.Add_Click({ Invoke-LogOperation "cleanup" "Deep Cleanup" })
$controls.BtnHealth.Add_Click({ Invoke-LogOperation "health" "Health Check" })
$controls.BtnRepair.Add_Click({ Invoke-LogOperation "repair" "Repair" })
$controls.BtnAbout.Add_Click({ Show-Panel "About" "About" "BtnAbout" })
$controls.BtnHelp.Add_Click({ Show-Help "Overview" })
$controls.BtnSettings.Add_Click({ Show-SettingsDialog })

# Cancel operation button
$controls.BtnCancelOp.Add_Click({
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        try {
            $script:CurrentProcess.Kill()
            Write-LogOutput "Operation cancelled by user" -Level Warning
        } catch {
            Write-LogOutput "Failed to cancel operation: $_" -Level Error
        }
    }
    $script:OperationRunning = $false
    Enable-OperationButtons
    $controls.BtnCancelOp.Visibility = "Collapsed"
    Set-Status "Ready"
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
    if ($script:CurrentProcess -and !$script:CurrentProcess.HasExited) { $script:CurrentProcess.Kill() }
    $controls.BtnCancel.Visibility = "Collapsed"
})
#endregion

#region Initialize
$controls.VersionLabel.Text = "v$script:AppVersion"
$controls.AboutVersion.Text = "Version $script:AppVersion"
$controls.AdminBadge.Text = if($script:IsAdmin){"Admin"}else{"Limited"}
$controls.AdminBadge.Foreground = if($script:IsAdmin){"#3FB950"}else{"#D29922"}

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

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({
    if ($controls.DashboardPanel.Visibility -eq "Visible" -and -not $script:RefreshInProgress) {
        $script:RefreshInProgress = $true
        try { Update-Dashboard } finally { $script:RefreshInProgress = $false }
    }
})
$timer.Start()

$window.Add_Closing({
    $timer.Stop()
    if ($script:CurrentProcess -and !$script:CurrentProcess.HasExited) { $script:CurrentProcess.Kill() }
})
#endregion

#region Main Entry Point with Error Handling
$script:StartupDuration = ((Get-Date) - $script:StartupTime).TotalMilliseconds
Write-Log "Startup completed in $([math]::Round($script:StartupDuration, 0))ms"
Write-Log "Running WPF form"

try {
    $window.ShowDialog() | Out-Null
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
        if ($script:CurrentProcess -and !$script:CurrentProcess.HasExited) {
            $script:CurrentProcess.Kill()
        }
    }
    catch {
        Write-Log "Cleanup warning: $_"
    }
}

Write-Log "=== Application closed ==="
#endregion

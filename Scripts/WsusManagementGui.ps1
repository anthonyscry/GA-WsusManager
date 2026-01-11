#Requires -Version 5.1
<#
===============================================================================
Script: WsusManagementGui.ps1
Author: Tony Tran, ISSO, Classified Computing, GA-ASI
Version: 3.5.0
===============================================================================
.SYNOPSIS
    WSUS Manager GUI - Modern WPF interface for WSUS management
.DESCRIPTION
    Portable GUI for managing WSUS servers with SQL Express.
    Features: Dashboard, Health checks, Maintenance, Import/Export
#>

param([switch]$SkipAdminCheck)

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$script:AppVersion = "3.5.2"

#region Script Path Detection
$script:ScriptRoot = $null
$exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ($exePath -and $exePath -notmatch 'powershell\.exe$|pwsh\.exe$') {
    $script:ScriptRoot = Split-Path -Parent $exePath
} elseif ($PSScriptRoot) {
    $script:ScriptRoot = $PSScriptRoot
} else {
    $script:ScriptRoot = (Get-Location).Path
}
#endregion

#region Settings
$script:LogDir = "C:\WSUS\Logs"
$script:LogPath = Join-Path $script:LogDir "WsusGui_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:SettingsFile = Join-Path $env:APPDATA "WsusManager\settings.json"
$script:ContentPath = "C:\WSUS"
$script:SqlInstance = ".\SQLEXPRESS"
$script:ExportRoot = "C:\"
$script:ServerMode = "Online"  # "Online" or "AirGap"

function Write-Log {
    param([string]$Msg)
    try {
        if (!(Test-Path $script:LogDir)) { New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null }
        "[$(Get-Date -Format 'HH:mm:ss')] $Msg" | Add-Content -Path $script:LogPath -ErrorAction SilentlyContinue
    } catch {}
}

function Load-Settings {
    try {
        if (Test-Path $script:SettingsFile) {
            $s = Get-Content $script:SettingsFile -Raw | ConvertFrom-Json
            if ($s.ContentPath) { $script:ContentPath = $s.ContentPath }
            if ($s.SqlInstance) { $script:SqlInstance = $s.SqlInstance }
            if ($s.ExportRoot) { $script:ExportRoot = $s.ExportRoot }
            if ($s.ServerMode) { $script:ServerMode = $s.ServerMode }
        }
    } catch {}
}

function Save-Settings {
    try {
        $dir = Split-Path $script:SettingsFile -Parent
        if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        @{ ContentPath=$script:ContentPath; SqlInstance=$script:SqlInstance; ExportRoot=$script:ExportRoot; ServerMode=$script:ServerMode } |
            ConvertTo-Json | Set-Content $script:SettingsFile -Encoding UTF8
    } catch {}
}

Load-Settings
Write-Log "=== Starting v$script:AppVersion ==="
#endregion

#region Admin Check
$script:IsAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    $script:IsAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {}
#endregion

#region XAML Definition
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="WSUS Manager"
    Height="700"
    Width="1100"
    MinHeight="600"
    MinWidth="900"
    WindowStartupLocation="CenterScreen"
    Background="#0D1117">

    <Window.Resources>
        <!-- Color Palette -->
        <Color x:Key="BgDark">#0D1117</Color>
        <Color x:Key="BgSidebar">#161B22</Color>
        <Color x:Key="BgCard">#21262D</Color>
        <Color x:Key="BorderColor">#30363D</Color>
        <Color x:Key="AccentBlue">#58A6FF</Color>
        <Color x:Key="AccentGreen">#3FB950</Color>
        <Color x:Key="AccentOrange">#D29922</Color>
        <Color x:Key="AccentRed">#F85149</Color>
        <Color x:Key="TextPrimary">#E6EDF3</Color>
        <Color x:Key="TextSecondary">#8B949E</Color>
        <Color x:Key="TextMuted">#484F58</Color>

        <SolidColorBrush x:Key="BgDarkBrush" Color="{StaticResource BgDark}"/>
        <SolidColorBrush x:Key="BgSidebarBrush" Color="{StaticResource BgSidebar}"/>
        <SolidColorBrush x:Key="BgCardBrush" Color="{StaticResource BgCard}"/>
        <SolidColorBrush x:Key="BorderBrush" Color="{StaticResource BorderColor}"/>
        <SolidColorBrush x:Key="AccentBlueBrush" Color="{StaticResource AccentBlue}"/>
        <SolidColorBrush x:Key="AccentGreenBrush" Color="{StaticResource AccentGreen}"/>
        <SolidColorBrush x:Key="AccentOrangeBrush" Color="{StaticResource AccentOrange}"/>
        <SolidColorBrush x:Key="AccentRedBrush" Color="{StaticResource AccentRed}"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="{StaticResource TextPrimary}"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="{StaticResource TextSecondary}"/>
        <SolidColorBrush x:Key="TextMutedBrush" Color="{StaticResource TextMuted}"/>

        <!-- Navigation Button Style -->
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="Padding" Value="16,12"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#21262D"/>
                                <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Primary Button Style -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource AccentBlueBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#79C0FF"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#30363D"/>
                                <Setter Property="Foreground" Value="#484F58"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary Button Style -->
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource BgCardBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#30363D"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Success Button Style -->
        <Style x:Key="SuccessButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource AccentGreenBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#56D364"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger Button Style -->
        <Style x:Key="DangerButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource AccentRedBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#FF6B61"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="220"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="{StaticResource BgSidebarBrush}">
            <DockPanel>
                <!-- Logo Section -->
                <StackPanel DockPanel.Dock="Top" Margin="16,20,16,0">
                    <TextBlock Text="WSUS Manager" FontSize="18" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}"/>
                    <TextBlock x:Name="VersionLabel" Text="v3.5.0" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>

                    <!-- Server Mode Toggle -->
                    <Border Background="{StaticResource BgCardBrush}" CornerRadius="4" Margin="0,12,0,0" Padding="8,6">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                <TextBlock x:Name="ServerModeLabel" Text="Online" FontSize="12" FontWeight="SemiBold" Foreground="{StaticResource AccentGreenBrush}"/>
                                <TextBlock Text="Server Mode" FontSize="10" Foreground="{StaticResource TextMutedBrush}"/>
                            </StackPanel>
                            <Button x:Name="BtnToggleMode" Grid.Column="1" Content="Switch" Style="{StaticResource SecondaryButton}" Padding="8,4" FontSize="10"/>
                        </Grid>
                    </Border>
                </StackPanel>

                <!-- Settings/About at bottom -->
                <StackPanel DockPanel.Dock="Bottom" Margin="8,0,8,16">
                    <Button x:Name="BtnSettings" Content="Settings" Style="{StaticResource NavButton}" Foreground="{StaticResource TextSecondaryBrush}"/>
                    <Button x:Name="BtnAbout" Content="About" Style="{StaticResource NavButton}" Foreground="{StaticResource TextSecondaryBrush}"/>
                </StackPanel>

                <!-- Navigation Menu -->
                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,20,0,0">
                    <StackPanel>
                        <Button x:Name="BtnDashboard" Content="Dashboard" Style="{StaticResource NavButton}" Margin="8,0" Background="#21262D" Foreground="{StaticResource TextPrimaryBrush}"/>

                        <TextBlock Text="SETUP" FontSize="11" FontWeight="Bold" Foreground="{StaticResource AccentBlueBrush}" Margin="16,20,0,8"/>
                        <Button x:Name="BtnInstall" Content="Install WSUS" Style="{StaticResource NavButton}" Margin="8,0"/>
                        <Button x:Name="BtnRestore" Content="Restore Database" Style="{StaticResource NavButton}" Margin="8,0"/>

                        <TextBlock Text="DATA TRANSFER" FontSize="11" FontWeight="Bold" Foreground="{StaticResource AccentBlueBrush}" Margin="16,20,0,8"/>
                        <Button x:Name="BtnExport" Content="Export to Media" Style="{StaticResource NavButton}" Margin="8,0"/>
                        <Button x:Name="BtnImport" Content="Import from Media" Style="{StaticResource NavButton}" Margin="8,0"/>

                        <TextBlock Text="MAINTENANCE" FontSize="11" FontWeight="Bold" Foreground="{StaticResource AccentBlueBrush}" Margin="16,20,0,8"/>
                        <Button x:Name="BtnMaintenance" Content="Monthly Maintenance" Style="{StaticResource NavButton}" Margin="8,0"/>
                        <Button x:Name="BtnCleanup" Content="Deep Cleanup" Style="{StaticResource NavButton}" Margin="8,0"/>

                        <TextBlock Text="TROUBLESHOOTING" FontSize="11" FontWeight="Bold" Foreground="{StaticResource AccentBlueBrush}" Margin="16,20,0,8"/>
                        <Button x:Name="BtnHealth" Content="Health Check" Style="{StaticResource NavButton}" Margin="8,0"/>
                        <Button x:Name="BtnRepair" Content="Health + Repair" Style="{StaticResource NavButton}" Margin="8,0"/>
                    </StackPanel>
                </ScrollViewer>
            </DockPanel>
        </Border>

        <!-- Main Content -->
        <Grid Grid.Column="1" Margin="24,16,24,16">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Header -->
            <DockPanel Grid.Row="0" Margin="0,0,0,16">
                <Border DockPanel.Dock="Right" Background="{StaticResource BgCardBrush}" CornerRadius="4" Padding="10,4" Margin="12,0,0,0" VerticalAlignment="Center">
                    <TextBlock x:Name="AdminBadge" Text="Administrator" FontSize="11" FontWeight="SemiBold" Foreground="{StaticResource AccentGreenBrush}"/>
                </Border>
                <TextBlock x:Name="PageTitle" Text="Dashboard" FontSize="24" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}" VerticalAlignment="Center"/>
            </DockPanel>

            <!-- Dashboard Panel -->
            <Grid x:Name="DashboardPanel" Grid.Row="1">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Status Cards -->
                <Grid Grid.Row="0" Margin="0,0,0,24">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="16"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="16"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="16"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Card 1: Services -->
                    <Border Grid.Column="0" Background="{StaticResource BgCardBrush}" CornerRadius="4">
                        <Grid>
                            <Border x:Name="Card1Bar" Height="4" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource AccentBlueBrush}"/>
                            <StackPanel Margin="16,20,16,16">
                                <TextBlock Text="Services" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"/>
                                <TextBlock x:Name="Card1Value" Text="..." FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,8,0,0"/>
                                <TextBlock x:Name="Card1Sub" Text="SQL, WSUS, IIS" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Card 2: Database -->
                    <Border Grid.Column="2" Background="{StaticResource BgCardBrush}" CornerRadius="4">
                        <Grid>
                            <Border x:Name="Card2Bar" Height="4" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource AccentGreenBrush}"/>
                            <StackPanel Margin="16,20,16,16">
                                <TextBlock Text="Database" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"/>
                                <TextBlock x:Name="Card2Value" Text="..." FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,8,0,0"/>
                                <TextBlock x:Name="Card2Sub" Text="SUSDB" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Card 3: Disk Space -->
                    <Border Grid.Column="4" Background="{StaticResource BgCardBrush}" CornerRadius="4">
                        <Grid>
                            <Border x:Name="Card3Bar" Height="4" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource AccentOrangeBrush}"/>
                            <StackPanel Margin="16,20,16,16">
                                <TextBlock Text="Disk Space" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"/>
                                <TextBlock x:Name="Card3Value" Text="..." FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,8,0,0"/>
                                <TextBlock x:Name="Card3Sub" Text="Content storage" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Card 4: Automation -->
                    <Border Grid.Column="6" Background="{StaticResource BgCardBrush}" CornerRadius="4">
                        <Grid>
                            <Border x:Name="Card4Bar" Height="4" VerticalAlignment="Top" CornerRadius="4,4,0,0" Background="{StaticResource AccentBlueBrush}"/>
                            <StackPanel Margin="16,20,16,16">
                                <TextBlock Text="Automation" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"/>
                                <TextBlock x:Name="Card4Value" Text="..." FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,8,0,0"/>
                                <TextBlock x:Name="Card4Sub" Text="Scheduled task" FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>

                <!-- Quick Actions -->
                <StackPanel Grid.Row="1" Margin="0,0,0,24">
                    <TextBlock Text="Quick Actions" FontSize="14" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                    <WrapPanel>
                        <Button x:Name="QBtnHealth" Content="Health Check" Style="{StaticResource PrimaryButton}" Margin="0,0,8,0"/>
                        <Button x:Name="QBtnCleanup" Content="Deep Cleanup" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                        <Button x:Name="QBtnMaint" Content="Maintenance" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0"/>
                        <Button x:Name="QBtnStart" Content="Start Services" Style="{StaticResource SuccessButton}" Margin="0,0,8,0"/>
                    </WrapPanel>
                </StackPanel>

                <!-- Configuration -->
                <StackPanel Grid.Row="2">
                    <TextBlock Text="Configuration" FontSize="14" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                    <Border Background="{StaticResource BgCardBrush}" CornerRadius="4" Padding="16">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="120"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <TextBlock Grid.Row="0" Grid.Column="0" Text="Content Path:" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,8"/>
                            <TextBlock x:Name="CfgContentPath" Grid.Row="0" Grid.Column="1" Text="C:\WSUS" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>

                            <TextBlock Grid.Row="1" Grid.Column="0" Text="SQL Instance:" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,8"/>
                            <TextBlock x:Name="CfgSqlInstance" Grid.Row="1" Grid.Column="1" Text=".\SQLEXPRESS" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>

                            <TextBlock Grid.Row="2" Grid.Column="0" Text="Export Root:" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,8"/>
                            <TextBlock x:Name="CfgExportRoot" Grid.Row="2" Grid.Column="1" Text="C:\" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>

                            <TextBlock Grid.Row="3" Grid.Column="0" Text="Log File:" Foreground="{StaticResource TextSecondaryBrush}"/>
                            <TextBlock x:Name="CfgLogPath" Grid.Row="3" Grid.Column="1" Foreground="{StaticResource TextPrimaryBrush}"/>
                        </Grid>
                    </Border>
                </StackPanel>
            </Grid>

            <!-- Operation Panel (hidden by default) -->
            <Grid x:Name="OperationPanel" Grid.Row="1" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <Border Grid.Row="0" Background="{StaticResource BgCardBrush}" CornerRadius="4">
                    <ScrollViewer x:Name="ConsoleScroller" VerticalScrollBarVisibility="Auto" Margin="12">
                        <TextBlock x:Name="ConsoleOutput" FontFamily="Consolas" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </Border>

                <DockPanel Grid.Row="1" Margin="0,12,0,0">
                    <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource DangerButton}" DockPanel.Dock="Left" Visibility="Collapsed"/>
                    <Button x:Name="BtnBack" Content="Back to Dashboard" Style="{StaticResource SecondaryButton}" DockPanel.Dock="Right"/>
                </DockPanel>
            </Grid>

            <!-- About Panel (hidden by default) -->
            <ScrollViewer x:Name="AboutPanel" Grid.Row="1" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                <StackPanel>
                    <Border Background="{StaticResource BgCardBrush}" CornerRadius="4" Padding="20" Margin="0,0,0,16">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Company Logo -->
                            <Border Grid.Column="0" Width="80" Height="80" Background="#1A3A6E" CornerRadius="8" Margin="0,0,20,0">
                                <Image x:Name="AboutLogo" Width="64" Height="64" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>

                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock Text="WSUS Manager" FontSize="22" FontWeight="Bold" Foreground="{StaticResource TextPrimaryBrush}"/>
                                <TextBlock x:Name="AboutVersion" Text="Version 3.5.1" FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>
                                <TextBlock Text="Windows Server Update Services Management Tool" FontSize="12" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <Border Background="{StaticResource BgCardBrush}" CornerRadius="4" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Author" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                            <TextBlock Text="Tony Tran" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource AccentBlueBrush}"/>
                            <TextBlock Text="Information Systems Security Officer" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>
                            <TextBlock Text="Classified Computing, GA-ASI" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,2,0,0"/>
                            <TextBlock Text="tony.tran@ga-asi.com" FontSize="12" Foreground="{StaticResource AccentBlueBrush}" Margin="0,8,0,0"/>
                        </StackPanel>
                    </Border>

                    <Border Background="{StaticResource BgCardBrush}" CornerRadius="4" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="Description" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                            <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"
                                       Text="WSUS Manager is a comprehensive toolkit for deploying and managing Windows Server Update Services with SQL Server Express. It provides a modern GUI for server setup, database management, and air-gapped network support."/>
                            <TextBlock TextWrapping="Wrap" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,12,0,0"
                                       Text="Features include automated WSUS installation, database backup/restore, export/import for offline networks, monthly maintenance automation, health checks with auto-repair, and deep cleanup operations."/>
                        </StackPanel>
                    </Border>

                    <Border Background="{StaticResource BgCardBrush}" CornerRadius="4" Padding="20" Margin="0,0,0,16">
                        <StackPanel>
                            <TextBlock Text="System Requirements" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>

                                <TextBlock Grid.Row="0" Grid.Column="0" Text="Operating System" FontSize="12" Foreground="{StaticResource TextMutedBrush}"/>
                                <TextBlock Grid.Row="0" Grid.Column="1" Text="Windows Server 2019+" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"/>

                                <TextBlock Grid.Row="1" Grid.Column="0" Text="PowerShell" FontSize="12" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                                <TextBlock Grid.Row="1" Grid.Column="1" Text="Version 5.1 or higher" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>

                                <TextBlock Grid.Row="2" Grid.Column="0" Text="SQL Server" FontSize="12" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                                <TextBlock Grid.Row="2" Grid.Column="1" Text="SQL Server Express 2022" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>

                                <TextBlock Grid.Row="3" Grid.Column="0" Text="Disk Space" FontSize="12" Foreground="{StaticResource TextMutedBrush}" Margin="0,4,0,0"/>
                                <TextBlock Grid.Row="3" Grid.Column="1" Text="50GB+ recommended for updates" FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <Border Background="{StaticResource BgCardBrush}" CornerRadius="4" Padding="20">
                        <StackPanel>
                            <TextBlock Text="License" FontSize="14" FontWeight="SemiBold" Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                            <TextBlock Text="Internal Use Only - General Atomics Aeronautical Systems, Inc." FontSize="12" Foreground="{StaticResource TextSecondaryBrush}"/>
                            <TextBlock Text="© 2026 GA-ASI. All rights reserved." FontSize="11" Foreground="{StaticResource TextMutedBrush}" Margin="0,8,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>

            <!-- Status Bar -->
            <Border Grid.Row="2" Background="{StaticResource BgCardBrush}" CornerRadius="4" Margin="0,16,0,0" Padding="12,8">
                <TextBlock x:Name="StatusLabel" Text="Ready" FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
            </Border>
        </Grid>
    </Grid>
</Window>
"@
#endregion

#region Create Window
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$controls = @{}
$xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object {
    $name = $_.Name
    if ($name) { $controls[$name] = $window.FindName($name) }
}
#endregion

#region Helper Functions
function Get-ServiceStatus {
    $result = @{Running=0; Names=@()}
    foreach ($svc in @("MSSQL`$SQLEXPRESS","WSUSService","W3SVC")) {
        try {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq "Running") {
                $result.Running++
                $result.Names += switch($svc){"MSSQL`$SQLEXPRESS"{"SQL"}"WSUSService"{"WSUS"}"W3SVC"{"IIS"}}
            }
        } catch {}
    }
    return $result
}

function Get-DiskFreeGB {
    try {
        $d = Get-PSDrive -Name "C" -ErrorAction SilentlyContinue
        if ($d.Free) { return [math]::Round($d.Free/1GB,1) }
    } catch {}
    return 0
}

function Get-DatabaseSizeGB {
    # SQL Express has a 10GB limit - get current SUSDB size
    try {
        $sqlRunning = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
        if ($sqlRunning -and $sqlRunning.Status -eq "Running") {
            $query = "SELECT SUM(size * 8 / 1024.0) AS SizeMB FROM sys.master_files WHERE database_id = DB_ID('SUSDB')"
            $result = Invoke-Sqlcmd -ServerInstance $script:SqlInstance -Query $query -ErrorAction SilentlyContinue
            if ($result -and $result.SizeMB) {
                return [math]::Round($result.SizeMB / 1024, 2)
            }
        }
    } catch {}
    return -1  # -1 indicates unable to get size
}

function Get-TaskStatus {
    try {
        $t = Get-ScheduledTask -TaskName "WSUS Monthly Maintenance" -ErrorAction SilentlyContinue
        if ($t) { return $t.State.ToString() }
    } catch {}
    return "Not Set"
}

function Update-Dashboard {
    # Services card
    $svc = Get-ServiceStatus
    $controls.Card1Value.Text = if($svc.Running -eq 3){"All Running"}else{"$($svc.Running)/3 Running"}
    $controls.Card1Sub.Text = if($svc.Names.Count -gt 0){$svc.Names -join ", "}else{"Services stopped"}
    $controls.Card1Bar.Background = if($svc.Running -eq 3){
        $window.FindResource("AccentGreenBrush")
    }elseif($svc.Running -gt 0){
        $window.FindResource("AccentOrangeBrush")
    }else{
        $window.FindResource("AccentRedBrush")
    }

    # Database card - show size out of 10GB limit with color coding
    $dbSize = Get-DatabaseSizeGB
    if ($dbSize -ge 0) {
        $controls.Card2Value.Text = "$dbSize / 10 GB"
        $controls.Card2Sub.Text = "SUSDB (SQL Express)"
        # Color based on how close to 10GB limit: <7=green, 7-9=yellow, >9=red
        $controls.Card2Bar.Background = if($dbSize -ge 9){
            $window.FindResource("AccentRedBrush")
        }elseif($dbSize -ge 7){
            $window.FindResource("AccentOrangeBrush")
        }else{
            $window.FindResource("AccentGreenBrush")
        }
    } else {
        $controls.Card2Value.Text = "Offline"
        $controls.Card2Sub.Text = "SQL not running"
        $controls.Card2Bar.Background = $window.FindResource("AccentOrangeBrush")
    }

    # Disk card
    $disk = Get-DiskFreeGB
    $controls.Card3Value.Text = "$disk GB Free"
    $controls.Card3Bar.Background = if($disk -lt 10){
        $window.FindResource("AccentRedBrush")
    }elseif($disk -lt 50){
        $window.FindResource("AccentOrangeBrush")
    }else{
        $window.FindResource("AccentGreenBrush")
    }

    # Task card
    $task = Get-TaskStatus
    $controls.Card4Value.Text = $task
    $controls.Card4Bar.Background = if($task -eq "Ready"){
        $window.FindResource("AccentGreenBrush")
    }else{
        $window.FindResource("AccentOrangeBrush")
    }

    # Config
    $controls.CfgContentPath.Text = $script:ContentPath
    $controls.CfgSqlInstance.Text = $script:SqlInstance
    $controls.CfgExportRoot.Text = $script:ExportRoot
    $controls.CfgLogPath.Text = $script:LogPath

    $controls.StatusLabel.Text = "Last refresh: $(Get-Date -Format 'HH:mm:ss')"
}

function Set-ActiveNavButton {
    param([string]$ActiveButton)
    $navButtons = @("BtnDashboard","BtnInstall","BtnRestore","BtnExport","BtnImport","BtnMaintenance","BtnCleanup","BtnHealth","BtnRepair","BtnAbout")
    foreach ($btn in $navButtons) {
        if ($controls[$btn]) {
            $isActive = ($btn -eq $ActiveButton)
            $controls[$btn].Background = if($isActive){$window.FindResource("BgCardBrush")}else{[System.Windows.Media.Brushes]::Transparent}
            $controls[$btn].Foreground = if($isActive){$window.FindResource("TextPrimaryBrush")}else{$window.FindResource("TextSecondaryBrush")}
        }
    }
}

function Show-Dashboard {
    $controls.PageTitle.Text = "Dashboard"
    $controls.DashboardPanel.Visibility = "Visible"
    $controls.OperationPanel.Visibility = "Collapsed"
    $controls.AboutPanel.Visibility = "Collapsed"
    Set-ActiveNavButton "BtnDashboard"
    Update-Dashboard
}

function Show-About {
    $controls.PageTitle.Text = "About"
    $controls.DashboardPanel.Visibility = "Collapsed"
    $controls.OperationPanel.Visibility = "Collapsed"
    $controls.AboutPanel.Visibility = "Visible"
    Set-ActiveNavButton "BtnAbout"
}

function Update-ServerModeUI {
    # Update the mode label and color
    if ($script:ServerMode -eq "Online") {
        $controls.ServerModeLabel.Text = "Online"
        $controls.ServerModeLabel.Foreground = $window.FindResource("AccentGreenBrush")
    } else {
        $controls.ServerModeLabel.Text = "Air-Gap"
        $controls.ServerModeLabel.Foreground = $window.FindResource("AccentOrangeBrush")
    }

    # Show/hide menu items based on mode
    # Online-only: Export, Monthly Maintenance
    # Air-Gap-only: Import
    if ($script:ServerMode -eq "Online") {
        $controls.BtnExport.Visibility = "Visible"
        $controls.BtnMaintenance.Visibility = "Visible"
        $controls.BtnImport.Visibility = "Collapsed"
        # Update Quick Actions
        $controls.QBtnMaint.Visibility = "Visible"
    } else {
        $controls.BtnExport.Visibility = "Collapsed"
        $controls.BtnMaintenance.Visibility = "Collapsed"
        $controls.BtnImport.Visibility = "Visible"
        # Update Quick Actions
        $controls.QBtnMaint.Visibility = "Collapsed"
    }
}

function Write-Console {
    param([string]$Text, [string]$Color = "Gray")
    $controls.ConsoleOutput.Inlines.Add((New-Object System.Windows.Documents.Run -ArgumentList "$Text`n"))
    $controls.ConsoleScroller.ScrollToEnd()
}

function Show-ExportDialog {
    $result = @{ Cancelled = $true; ExportType = "Full"; DestinationPath = ""; DaysOld = 30 }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Export to Media"
    $dlg.Width = 500
    $dlg.Height = 400
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $window
    $dlg.Background = $window.FindResource("BgDarkBrush")
    $dlg.ResizeMode = "NoResize"

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "24"

    # Title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Export WSUS Data"
    $title.FontSize = 16
    $title.FontWeight = "Bold"
    $title.Foreground = $window.FindResource("TextPrimaryBrush")
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    # Description
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "This will export the WSUS database (SUSDB) and content files to the selected location."
    $desc.Foreground = $window.FindResource("TextSecondaryBrush")
    $desc.TextWrapping = "Wrap"
    $desc.Margin = "0,0,0,16"
    $stack.Children.Add($desc)

    # Export Type
    $typeLbl = New-Object System.Windows.Controls.TextBlock
    $typeLbl.Text = "Export Type:"
    $typeLbl.Foreground = $window.FindResource("TextSecondaryBrush")
    $typeLbl.Margin = "0,0,0,8"
    $stack.Children.Add($typeLbl)

    $radioPanel = New-Object System.Windows.Controls.StackPanel
    $radioPanel.Orientation = "Horizontal"
    $radioPanel.Margin = "0,0,0,16"

    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full Export"
    $radioFull.Foreground = $window.FindResource("TextPrimaryBrush")
    $radioFull.IsChecked = $true
    $radioFull.Margin = "0,0,24,0"
    $radioPanel.Children.Add($radioFull)

    $radioDiff = New-Object System.Windows.Controls.RadioButton
    $radioDiff.Content = "Differential Export"
    $radioDiff.Foreground = $window.FindResource("TextPrimaryBrush")
    $radioPanel.Children.Add($radioDiff)

    $stack.Children.Add($radioPanel)

    # Days Old panel (for differential)
    $daysPanel = New-Object System.Windows.Controls.StackPanel
    $daysPanel.Orientation = "Horizontal"
    $daysPanel.Margin = "0,0,0,16"
    $daysPanel.Visibility = "Collapsed"

    $daysLbl = New-Object System.Windows.Controls.TextBlock
    $daysLbl.Text = "Export updates from the last"
    $daysLbl.Foreground = $window.FindResource("TextSecondaryBrush")
    $daysLbl.VerticalAlignment = "Center"
    $daysLbl.Margin = "0,0,8,0"
    $daysPanel.Children.Add($daysLbl)

    $daysTxt = New-Object System.Windows.Controls.TextBox
    $daysTxt.Text = "30"
    $daysTxt.Width = 50
    $daysTxt.Background = $window.FindResource("BgCardBrush")
    $daysTxt.Foreground = $window.FindResource("TextPrimaryBrush")
    $daysTxt.BorderBrush = $window.FindResource("BorderBrush")
    $daysTxt.Padding = "6,4"
    $daysTxt.HorizontalContentAlignment = "Center"
    $daysPanel.Children.Add($daysTxt)

    $daysLbl2 = New-Object System.Windows.Controls.TextBlock
    $daysLbl2.Text = "days"
    $daysLbl2.Foreground = $window.FindResource("TextSecondaryBrush")
    $daysLbl2.VerticalAlignment = "Center"
    $daysLbl2.Margin = "8,0,0,0"
    $daysPanel.Children.Add($daysLbl2)

    $stack.Children.Add($daysPanel)

    # Toggle days panel visibility based on radio selection
    $radioDiff.Add_Checked({ $daysPanel.Visibility = "Visible" }.GetNewClosure())
    $radioFull.Add_Checked({ $daysPanel.Visibility = "Collapsed" }.GetNewClosure())

    # Destination
    $destLbl = New-Object System.Windows.Controls.TextBlock
    $destLbl.Text = "Destination Folder:"
    $destLbl.Foreground = $window.FindResource("TextSecondaryBrush")
    $destLbl.Margin = "0,0,0,8"
    $stack.Children.Add($destLbl)

    $destPanel = New-Object System.Windows.Controls.DockPanel
    $destPanel.Margin = "0,0,0,24"

    $destBtn = New-Object System.Windows.Controls.Button
    $destBtn.Content = "Browse..."
    $destBtn.Style = $window.FindResource("SecondaryButton")
    $destBtn.Padding = "12,6"
    [System.Windows.Controls.DockPanel]::SetDock($destBtn, "Right")
    $destPanel.Children.Add($destBtn)

    $destTxt = New-Object System.Windows.Controls.TextBox
    $destTxt.Margin = "0,0,8,0"
    $destTxt.Background = $window.FindResource("BgCardBrush")
    $destTxt.Foreground = $window.FindResource("TextPrimaryBrush")
    $destTxt.BorderBrush = $window.FindResource("BorderBrush")
    $destTxt.Padding = "8,6"
    $destPanel.Children.Add($destTxt)

    $destBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select destination folder for export"
        if ($fbd.ShowDialog() -eq "OK") { $destTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())

    $stack.Children.Add($destPanel)

    # Buttons
    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $exportBtn = New-Object System.Windows.Controls.Button
    $exportBtn.Content = "Export"
    $exportBtn.Style = $window.FindResource("PrimaryButton")
    $exportBtn.Margin = "0,0,8,0"
    $exportBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($destTxt.Text)) {
            [System.Windows.MessageBox]::Show("Please select a destination folder.", "Export", "OK", "Warning")
            return
        }
        $result.Cancelled = $false
        $result.ExportType = if ($radioFull.IsChecked) { "Full" } else { "Differential" }
        $result.DestinationPath = $destTxt.Text
        $result.DaysOld = [int]$daysTxt.Text
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($exportBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Style = $window.FindResource("SecondaryButton")
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
    $dlg.Width = 500
    $dlg.Height = 280
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $window
    $dlg.Background = $window.FindResource("BgDarkBrush")
    $dlg.ResizeMode = "NoResize"

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "24"

    # Title
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Import WSUS Data"
    $title.FontSize = 16
    $title.FontWeight = "Bold"
    $title.Foreground = $window.FindResource("TextPrimaryBrush")
    $title.Margin = "0,0,0,16"
    $stack.Children.Add($title)

    # Description
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Select the folder containing the exported WSUS data (database backup and content files)."
    $desc.Foreground = $window.FindResource("TextSecondaryBrush")
    $desc.TextWrapping = "Wrap"
    $desc.Margin = "0,0,0,20"
    $stack.Children.Add($desc)

    # Source
    $srcLbl = New-Object System.Windows.Controls.TextBlock
    $srcLbl.Text = "Source Folder:"
    $srcLbl.Foreground = $window.FindResource("TextSecondaryBrush")
    $srcLbl.Margin = "0,0,0,8"
    $stack.Children.Add($srcLbl)

    $srcPanel = New-Object System.Windows.Controls.DockPanel
    $srcPanel.Margin = "0,0,0,24"

    $srcBtn = New-Object System.Windows.Controls.Button
    $srcBtn.Content = "Browse..."
    $srcBtn.Style = $window.FindResource("SecondaryButton")
    $srcBtn.Padding = "12,6"
    [System.Windows.Controls.DockPanel]::SetDock($srcBtn, "Right")
    $srcPanel.Children.Add($srcBtn)

    $srcTxt = New-Object System.Windows.Controls.TextBox
    $srcTxt.Margin = "0,0,8,0"
    $srcTxt.Background = $window.FindResource("BgCardBrush")
    $srcTxt.Foreground = $window.FindResource("TextPrimaryBrush")
    $srcTxt.BorderBrush = $window.FindResource("BorderBrush")
    $srcTxt.Padding = "8,6"
    $srcPanel.Children.Add($srcTxt)

    $srcBtn.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select folder containing exported WSUS data"
        if ($fbd.ShowDialog() -eq "OK") { $srcTxt.Text = $fbd.SelectedPath }
    }.GetNewClosure())

    $stack.Children.Add($srcPanel)

    # Buttons
    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $importBtn = New-Object System.Windows.Controls.Button
    $importBtn.Content = "Import"
    $importBtn.Style = $window.FindResource("PrimaryButton")
    $importBtn.Margin = "0,0,8,0"
    $importBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($srcTxt.Text)) {
            [System.Windows.MessageBox]::Show("Please select a source folder.", "Import", "OK", "Warning")
            return
        }
        $result.Cancelled = $false
        $result.SourcePath = $srcTxt.Text
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($importBtn)

    $cancelBtn = New-Object System.Windows.Controls.Button
    $cancelBtn.Content = "Cancel"
    $cancelBtn.Style = $window.FindResource("SecondaryButton")
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $stack.Children.Add($btnPanel)
    $dlg.Content = $stack
    $dlg.ShowDialog() | Out-Null

    return $result
}

function Show-RestoreWarning {
    $msg = "IMPORTANT: Before restoring, ensure:`n`n"
    $msg += "  - Database backup (.bak) is saved to: C:\WSUS`n"
    $msg += "  - Update files are copied to: C:\WSUS\WsusContent`n`n"
    $msg += "Do you want to proceed with the restore?"

    $result = [System.Windows.MessageBox]::Show($msg, "Restore Database - Warning", "YesNo", "Warning")
    return ($result -eq "Yes")
}

function Run-Operation {
    param([string]$Id, [string]$Title)

    Write-Log "Run-Op: $Id"
    $controls.PageTitle.Text = $Title
    $controls.DashboardPanel.Visibility = "Collapsed"
    $controls.OperationPanel.Visibility = "Visible"
    $controls.ConsoleOutput.Inlines.Clear()
    $controls.BtnCancel.Visibility = "Visible"

    $sr = $script:ScriptRoot
    # Scripts are in the same folder when running from source, or in Scripts subfolder when running compiled
    $mgmt = Join-Path $sr "Invoke-WsusManagement.ps1"
    if (-not (Test-Path $mgmt)) { $mgmt = Join-Path $sr "Scripts\Invoke-WsusManagement.ps1" }
    $maint = Join-Path $sr "Invoke-WsusMonthlyMaintenance.ps1"
    if (-not (Test-Path $maint)) { $maint = Join-Path $sr "Scripts\Invoke-WsusMonthlyMaintenance.ps1" }
    $cp = $script:ContentPath
    $sql = $script:SqlInstance
    $exp = $script:ExportRoot

    $cmd = switch ($Id) {
        "install" {
            $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fbd.Description = "Select folder containing WSUS setup files"
            if ($fbd.ShowDialog() -eq "OK") {
                "& '$($fbd.SelectedPath)\Install-WsusWithSqlExpress.ps1'"
            } else { Show-Dashboard; return }
        }
        "restore" {
            if (!(Show-RestoreWarning)) { Show-Dashboard; return }
            "& '$mgmt' -Restore -ContentPath '$cp' -SqlInstance '$sql'"
        }
        "import" {
            $importOpts = Show-ImportDialog
            if ($importOpts.Cancelled) { Show-Dashboard; return }
            $srcPath = $importOpts.SourcePath
            "& '$mgmt' -Import -ContentPath '$cp' -ExportRoot '$srcPath'"
        }
        "export" {
            $exportOpts = Show-ExportDialog
            if ($exportOpts.Cancelled) { Show-Dashboard; return }
            $destPath = $exportOpts.DestinationPath
            $exportType = $exportOpts.ExportType
            $daysOld = $exportOpts.DaysOld
            if ($exportType -eq "Differential") {
                "& '$mgmt' -Export -ContentPath '$cp' -ExportRoot '$destPath' -Differential -DaysOld $daysOld"
            } else {
                "& '$mgmt' -Export -ContentPath '$cp' -ExportRoot '$destPath'"
            }
        }
        "maintenance" { "& '$maint'" }
        "cleanup"     { "& '$mgmt' -Cleanup -Force -SqlInstance '$sql'" }
        "health"      { "& '$mgmt' -Health -ContentPath '$cp' -SqlInstance '$sql'" }
        "repair"      { "& '$mgmt' -Repair -ContentPath '$cp' -SqlInstance '$sql'" }
        default       { "Write-Host 'Unknown: $Id'" }
    }

    Write-Console "Command: $cmd" "Gray"
    Write-Console ""

    $script:CurrentProcess = $null
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

        $outputHandler = {
            $line = $Event.SourceEventArgs.Data
            if ($line) {
                $window.Dispatcher.Invoke([Action]{
                    $run = New-Object System.Windows.Documents.Run -ArgumentList "$line`n"
                    if ($line -match 'ERROR|FAIL|Exception') {
                        $run.Foreground = [System.Windows.Media.Brushes]::Crimson
                    } elseif ($line -match 'WARN') {
                        $run.Foreground = [System.Windows.Media.Brushes]::Orange
                    } elseif ($line -match 'OK|Success|Complete') {
                        $run.Foreground = [System.Windows.Media.Brushes]::ForestGreen
                    } else {
                        $run.Foreground = [System.Windows.Media.Brushes]::Gray
                    }
                    $controls.ConsoleOutput.Inlines.Add($run)
                    $controls.ConsoleScroller.ScrollToEnd()
                })
            }
        }

        $exitHandler = {
            $window.Dispatcher.Invoke([Action]{
                $run = New-Object System.Windows.Documents.Run -ArgumentList "`n=== Completed ==="
                $run.Foreground = [System.Windows.Media.Brushes]::DodgerBlue
                $controls.ConsoleOutput.Inlines.Add($run)
                $controls.BtnCancel.Visibility = "Collapsed"
                $controls.StatusLabel.Text = "Completed"
            })
        }

        Register-ObjectEvent -InputObject $script:CurrentProcess -EventName OutputDataReceived -Action $outputHandler | Out-Null
        Register-ObjectEvent -InputObject $script:CurrentProcess -EventName ErrorDataReceived -Action $outputHandler | Out-Null
        Register-ObjectEvent -InputObject $script:CurrentProcess -EventName Exited -Action $exitHandler | Out-Null

        $script:CurrentProcess.Start() | Out-Null
        $script:CurrentProcess.BeginOutputReadLine()
        $script:CurrentProcess.BeginErrorReadLine()
        $controls.StatusLabel.Text = "Running: $Title"
    } catch {
        Write-Console "ERROR: $_" "Red"
        $controls.BtnCancel.Visibility = "Collapsed"
    }
}
#endregion

#region Event Handlers
# Navigation
$controls.BtnDashboard.Add_Click({ Show-Dashboard })
$controls.BtnInstall.Add_Click({ Run-Operation "install" "Install WSUS + SQL" })
$controls.BtnRestore.Add_Click({ Run-Operation "restore" "Restore Database" })
$controls.BtnExport.Add_Click({ Run-Operation "export" "Export to Media" })
$controls.BtnImport.Add_Click({ Run-Operation "import" "Import from Media" })
$controls.BtnMaintenance.Add_Click({ Run-Operation "maintenance" "Monthly Maintenance" })
$controls.BtnCleanup.Add_Click({ Run-Operation "cleanup" "Deep Cleanup" })
$controls.BtnHealth.Add_Click({ Run-Operation "health" "Health Check" })
$controls.BtnRepair.Add_Click({ Run-Operation "repair" "Health + Repair" })
$controls.BtnAbout.Add_Click({ Show-About })

# Server Mode Toggle
$controls.BtnToggleMode.Add_Click({
    if ($script:ServerMode -eq "Online") {
        $script:ServerMode = "AirGap"
    } else {
        $script:ServerMode = "Online"
    }
    Save-Settings
    Update-ServerModeUI
    Write-Log "Server mode changed to: $script:ServerMode"
})

# Quick actions
$controls.QBtnHealth.Add_Click({ Run-Operation "health" "Health Check" })
$controls.QBtnCleanup.Add_Click({ Run-Operation "cleanup" "Deep Cleanup" })
$controls.QBtnMaint.Add_Click({ Run-Operation "maintenance" "Monthly Maintenance" })
$controls.QBtnStart.Add_Click({
    $controls.QBtnStart.IsEnabled = $false
    $controls.QBtnStart.Content = "Starting..."
    @("MSSQL`$SQLEXPRESS","W3SVC","WSUSService") | ForEach-Object {
        try { Start-Service -Name $_ -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Seconds 2
    Update-Dashboard
    $controls.QBtnStart.Content = "Start Services"
    $controls.QBtnStart.IsEnabled = $true
})

# Back and Cancel
$controls.BtnBack.Add_Click({ Show-Dashboard })
$controls.BtnCancel.Add_Click({
    if ($script:CurrentProcess -and !$script:CurrentProcess.HasExited) {
        $script:CurrentProcess.Kill()
    }
    $controls.BtnCancel.Visibility = "Collapsed"
})

# Settings
$controls.BtnSettings.Add_Click({
    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Settings"
    $dlg.Width = 450
    $dlg.Height = 280
    $dlg.WindowStartupLocation = "CenterOwner"
    $dlg.Owner = $window
    $dlg.Background = $window.FindResource("BgDarkBrush")
    $dlg.ResizeMode = "NoResize"

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = "20"

    for ($i = 0; $i -lt 5; $i++) {
        $row = New-Object System.Windows.Controls.RowDefinition
        $row.Height = "Auto"
        $grid.RowDefinitions.Add($row)
    }

    # Content Path
    $lbl1 = New-Object System.Windows.Controls.TextBlock
    $lbl1.Text = "WSUS Content Path:"
    $lbl1.Foreground = $window.FindResource("TextSecondaryBrush")
    $lbl1.Margin = "0,0,0,8"
    [System.Windows.Controls.Grid]::SetRow($lbl1, 0)
    $grid.Children.Add($lbl1)

    $txt1 = New-Object System.Windows.Controls.TextBox
    $txt1.Text = $script:ContentPath
    $txt1.Margin = "0,0,0,16"
    $txt1.Background = $window.FindResource("BgCardBrush")
    $txt1.Foreground = $window.FindResource("TextPrimaryBrush")
    $txt1.BorderBrush = $window.FindResource("BorderBrush")
    $txt1.Padding = "8,6"
    [System.Windows.Controls.Grid]::SetRow($txt1, 1)
    $grid.Children.Add($txt1)

    # SQL Instance
    $lbl2 = New-Object System.Windows.Controls.TextBlock
    $lbl2.Text = "SQL Instance:"
    $lbl2.Foreground = $window.FindResource("TextSecondaryBrush")
    $lbl2.Margin = "0,0,0,8"
    [System.Windows.Controls.Grid]::SetRow($lbl2, 2)
    $grid.Children.Add($lbl2)

    $txt2 = New-Object System.Windows.Controls.TextBox
    $txt2.Text = $script:SqlInstance
    $txt2.Margin = "0,0,0,16"
    $txt2.Background = $window.FindResource("BgCardBrush")
    $txt2.Foreground = $window.FindResource("TextPrimaryBrush")
    $txt2.BorderBrush = $window.FindResource("BorderBrush")
    $txt2.Padding = "8,6"
    [System.Windows.Controls.Grid]::SetRow($txt2, 3)
    $grid.Children.Add($txt2)

    # Buttons
    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"
    [System.Windows.Controls.Grid]::SetRow($btnPanel, 4)

    $saveBtn = New-Object System.Windows.Controls.Button
    $saveBtn.Content = "Save"
    $saveBtn.Style = $window.FindResource("PrimaryButton")
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
    $cancelBtn.Style = $window.FindResource("SecondaryButton")
    $cancelBtn.Add_Click({ $dlg.Close() }.GetNewClosure())
    $btnPanel.Children.Add($cancelBtn)

    $grid.Children.Add($btnPanel)
    $dlg.Content = $grid
    $dlg.ShowDialog() | Out-Null
})
#endregion

#region Initialize
$controls.VersionLabel.Text = "v$script:AppVersion"
$controls.AboutVersion.Text = "Version $script:AppVersion"
$controls.AdminBadge.Text = if($script:IsAdmin){"Administrator"}else{"Limited"}
$controls.AdminBadge.Foreground = if($script:IsAdmin){
    $window.FindResource("AccentGreenBrush")
}else{
    $window.FindResource("AccentOrangeBrush")
}

# Load window icon and About page logo
try {
    $iconPath = Join-Path $script:ScriptRoot "wsus-icon.ico"
    if (-not (Test-Path $iconPath)) {
        $iconPath = Join-Path (Split-Path -Parent $script:ScriptRoot) "wsus-icon.ico"
    }
    if (Test-Path $iconPath) {
        $iconUri = New-Object System.Uri $iconPath
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconUri)

        # Set About page logo
        if ($controls['AboutLogo']) {
            $aboutBitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $aboutBitmap.BeginInit()
            $aboutBitmap.UriSource = $iconUri
            $aboutBitmap.DecodePixelWidth = 64
            $aboutBitmap.EndInit()
            $controls['AboutLogo'].Source = $aboutBitmap
        }
    }
} catch {
    # Silently continue if icon loading fails
}

Update-Dashboard
Update-ServerModeUI

# Auto-refresh timer
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({ if ($controls.DashboardPanel.Visibility -eq "Visible") { Update-Dashboard } })
$timer.Start()

$window.Add_Closing({
    $timer.Stop()
    if ($script:CurrentProcess -and !$script:CurrentProcess.HasExited) {
        $script:CurrentProcess.Kill()
    }
})
#endregion

#region Run
Write-Log "Running WPF form"
$window.ShowDialog() | Out-Null
#endregion

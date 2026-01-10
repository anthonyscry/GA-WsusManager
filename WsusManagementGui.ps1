#Requires -Version 5.1
<#
===============================================================================
Script: WsusManagementGui.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 2.0.0
Date: 2026-01-10
===============================================================================
.SYNOPSIS
    Modern Windows Forms GUI for WSUS Management operations.

.DESCRIPTION
    Provides a clean, modern graphical interface for all WSUS management tasks:
    - Dashboard with real-time status
    - Installation, restoration, import/export
    - Maintenance and cleanup
    - Health checks and repairs

    Can be compiled to portable EXE using PS2EXE.

.NOTES
    Run Build-WsusGui.ps1 to compile to standalone EXE.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================================
# CONFIGURATION
# ============================================================================
$script:ScriptRoot = $PSScriptRoot
if (-not $script:ScriptRoot) {
    $script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$script:ContentPath = "C:\WSUS"
$script:SqlInstance = ".\SQLEXPRESS"
$script:ExportRoot = "\\lab-hyperv\d\WSUS-Exports"
$script:LogPath = "C:\WSUS\Logs\WsusGui_$(Get-Date -Format 'yyyy-MM-dd').log"

# ============================================================================
# COLOR SCHEME
# ============================================================================
$script:Colors = @{
    # Main colors
    Background     = [System.Drawing.Color]::FromArgb(250, 250, 252)
    Surface        = [System.Drawing.Color]::White
    Sidebar        = [System.Drawing.Color]::FromArgb(32, 36, 45)
    SidebarHover   = [System.Drawing.Color]::FromArgb(45, 50, 62)
    SidebarActive  = [System.Drawing.Color]::FromArgb(59, 130, 246)

    # Accent colors
    Primary        = [System.Drawing.Color]::FromArgb(59, 130, 246)
    PrimaryHover   = [System.Drawing.Color]::FromArgb(37, 99, 235)
    Success        = [System.Drawing.Color]::FromArgb(34, 197, 94)
    Warning        = [System.Drawing.Color]::FromArgb(251, 146, 60)
    Danger         = [System.Drawing.Color]::FromArgb(239, 68, 68)

    # Text colors
    TextPrimary    = [System.Drawing.Color]::FromArgb(30, 41, 59)
    TextSecondary  = [System.Drawing.Color]::FromArgb(100, 116, 139)
    TextLight      = [System.Drawing.Color]::White
    TextMuted      = [System.Drawing.Color]::FromArgb(148, 163, 184)

    # Border & dividers
    Border         = [System.Drawing.Color]::FromArgb(226, 232, 240)
    Divider        = [System.Drawing.Color]::FromArgb(241, 245, 249)

    # Console colors
    ConsoleBackground = [System.Drawing.Color]::FromArgb(15, 23, 42)
    ConsoleText    = [System.Drawing.Color]::FromArgb(148, 163, 184)
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
function Write-GuiLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    if ($script:LogPath) {
        $logDir = Split-Path $script:LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
    }
}

function Show-Notification {
    param([string]$Title, [string]$Message, [string]$Type = "Info")

    [System.Media.SystemSounds]::Exclamation.Play()

    if ($script:NotifyIcon) {
        $iconType = switch ($Type) {
            "Error"   { [System.Windows.Forms.ToolTipIcon]::Error }
            "Warning" { [System.Windows.Forms.ToolTipIcon]::Warning }
            default   { [System.Windows.Forms.ToolTipIcon]::Info }
        }
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Message
        $script:NotifyIcon.BalloonTipIcon = $iconType
        $script:NotifyIcon.ShowBalloonTip(3000)
    }

    Write-GuiLog "$Title - $Message" $Type.ToUpper()
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-RoundedButton {
    param(
        [string]$Text,
        [System.Drawing.Color]$BackColor,
        [System.Drawing.Color]$ForeColor,
        [System.Drawing.Size]$Size,
        [System.Drawing.Point]$Location,
        [scriptblock]$OnClick
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Size = $Size
    $btn.Location = $Location
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $BackColor
    $btn.ForeColor = $ForeColor
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $btn.Cursor = "Hand"

    if ($OnClick) {
        $btn.Add_Click($OnClick)
    }

    return $btn
}

# ============================================================================
# MAIN FORM
# ============================================================================
function New-WsusGui {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WSUS Manager"
    $form.Size = New-Object System.Drawing.Size(1100, 700)
    $form.StartPosition = "CenterScreen"
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.BackColor = $script:Colors.Background
    $form.FormBorderStyle = "Sizable"
    $form.MinimumSize = New-Object System.Drawing.Size(900, 600)

    # System tray icon
    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    $script:NotifyIcon.Text = "WSUS Manager"
    $script:NotifyIcon.Visible = $true

    # ========== SIDEBAR ==========
    $sidebar = New-Object System.Windows.Forms.Panel
    $sidebar.Dock = "Left"
    $sidebar.Width = 220
    $sidebar.BackColor = $script:Colors.Sidebar

    # Logo/Title area
    $logoPanel = New-Object System.Windows.Forms.Panel
    $logoPanel.Dock = "Top"
    $logoPanel.Height = 70
    $logoPanel.BackColor = $script:Colors.Sidebar

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "WSUS Manager"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = $script:Colors.TextLight
    $titleLabel.Location = New-Object System.Drawing.Point(16, 20)
    $titleLabel.AutoSize = $true
    $logoPanel.Controls.Add($titleLabel)

    $versionLabel = New-Object System.Windows.Forms.Label
    $versionLabel.Text = "v3.2.0"
    $versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $versionLabel.ForeColor = $script:Colors.TextMuted
    $versionLabel.Location = New-Object System.Drawing.Point(16, 45)
    $versionLabel.AutoSize = $true
    $logoPanel.Controls.Add($versionLabel)

    $sidebar.Controls.Add($logoPanel)

    # Navigation container
    $navContainer = New-Object System.Windows.Forms.Panel
    $navContainer.Location = New-Object System.Drawing.Point(0, 70)
    $navContainer.Size = New-Object System.Drawing.Size(220, 500)
    $navContainer.BackColor = $script:Colors.Sidebar

    # Menu items definition
    $menuItems = @(
        @{ Icon = [char]0x2302; Text = "Dashboard"; Id = "dashboard"; Section = $null },
        @{ Icon = ""; Text = ""; Id = ""; Section = "SETUP" },
        @{ Icon = [char]0x2699; Text = "Install WSUS"; Id = "install"; Section = $null },
        @{ Icon = [char]0x21BB; Text = "Restore Database"; Id = "restore"; Section = $null },
        @{ Icon = ""; Text = ""; Id = ""; Section = "DATA TRANSFER" },
        @{ Icon = [char]0x2191; Text = "Export to Media"; Id = "export"; Section = $null },
        @{ Icon = [char]0x2193; Text = "Import from Media"; Id = "import"; Section = $null },
        @{ Icon = ""; Text = ""; Id = ""; Section = "MAINTENANCE" },
        @{ Icon = [char]0x2714; Text = "Monthly Maintenance"; Id = "maintenance"; Section = $null },
        @{ Icon = [char]0x2672; Text = "Deep Cleanup"; Id = "cleanup"; Section = $null },
        @{ Icon = ""; Text = ""; Id = ""; Section = "TROUBLESHOOTING" },
        @{ Icon = [char]0x2661; Text = "Health Check"; Id = "health"; Section = $null },
        @{ Icon = [char]0x2692; Text = "Health + Repair"; Id = "repair"; Section = $null },
        @{ Icon = [char]0x21BA; Text = "Reset Content"; Id = "reset"; Section = $null }
    )

    $yPos = 10
    $script:NavButtons = @{}

    foreach ($item in $menuItems) {
        if ($item.Section) {
            # Section header
            $sectionLabel = New-Object System.Windows.Forms.Label
            $sectionLabel.Text = $item.Section
            $sectionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
            $sectionLabel.ForeColor = $script:Colors.TextMuted
            $sectionLabel.Location = New-Object System.Drawing.Point(16, $yPos)
            $sectionLabel.Size = New-Object System.Drawing.Size(188, 20)
            $navContainer.Controls.Add($sectionLabel)
            $yPos += 28
        }
        elseif ($item.Id) {
            # Nav button
            $navBtn = New-Object System.Windows.Forms.Button
            $navBtn.Text = "  $($item.Icon)   $($item.Text)"
            $navBtn.Size = New-Object System.Drawing.Size(204, 38)
            $navBtn.Location = New-Object System.Drawing.Point(8, $yPos)
            $navBtn.FlatStyle = "Flat"
            $navBtn.FlatAppearance.BorderSize = 0
            $navBtn.FlatAppearance.MouseOverBackColor = $script:Colors.SidebarHover
            $navBtn.BackColor = $script:Colors.Sidebar
            $navBtn.ForeColor = $script:Colors.TextLight
            $navBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
            $navBtn.TextAlign = "MiddleLeft"
            $navBtn.Cursor = "Hand"
            $navBtn.Tag = $item.Id

            $navBtn.Add_Click({
                $operationId = $this.Tag
                Select-NavItem -Id $operationId

                if ($operationId -eq "dashboard") {
                    Show-Dashboard
                } else {
                    Start-Operation -OperationId $operationId
                }
            })

            $navContainer.Controls.Add($navBtn)
            $script:NavButtons[$item.Id] = $navBtn
            $yPos += 40
        }
    }

    $sidebar.Controls.Add($navContainer)

    # Settings button at bottom
    $settingsBtn = New-Object System.Windows.Forms.Button
    $settingsBtn.Text = "  Settings"
    $settingsBtn.Size = New-Object System.Drawing.Size(204, 38)
    $settingsBtn.Location = New-Object System.Drawing.Point(8, 540)
    $settingsBtn.Anchor = "Bottom, Left"
    $settingsBtn.FlatStyle = "Flat"
    $settingsBtn.FlatAppearance.BorderSize = 0
    $settingsBtn.FlatAppearance.MouseOverBackColor = $script:Colors.SidebarHover
    $settingsBtn.BackColor = $script:Colors.Sidebar
    $settingsBtn.ForeColor = $script:Colors.TextMuted
    $settingsBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $settingsBtn.TextAlign = "MiddleLeft"
    $settingsBtn.Cursor = "Hand"
    $settingsBtn.Add_Click({ Show-SettingsDialog })
    $sidebar.Controls.Add($settingsBtn)

    $form.Controls.Add($sidebar)

    # ========== MAIN CONTENT AREA ==========
    $mainContent = New-Object System.Windows.Forms.Panel
    $mainContent.Dock = "Fill"
    $mainContent.BackColor = $script:Colors.Background
    $mainContent.Padding = New-Object System.Windows.Forms.Padding(24)

    # Header bar
    $headerBar = New-Object System.Windows.Forms.Panel
    $headerBar.Dock = "Top"
    $headerBar.Height = 60
    $headerBar.BackColor = $script:Colors.Background

    $script:PageTitle = New-Object System.Windows.Forms.Label
    $script:PageTitle.Text = "Dashboard"
    $script:PageTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $script:PageTitle.ForeColor = $script:Colors.TextPrimary
    $script:PageTitle.Location = New-Object System.Drawing.Point(24, 15)
    $script:PageTitle.AutoSize = $true
    $headerBar.Controls.Add($script:PageTitle)

    # Admin status badge
    $isAdmin = Test-IsAdmin
    $adminBadge = New-Object System.Windows.Forms.Label
    $adminBadge.Text = if ($isAdmin) { "Administrator" } else { "Standard User" }
    $adminBadge.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $adminBadge.ForeColor = if ($isAdmin) { $script:Colors.Success } else { $script:Colors.Warning }
    $adminBadge.BackColor = if ($isAdmin) {
        [System.Drawing.Color]::FromArgb(240, 253, 244)
    } else {
        [System.Drawing.Color]::FromArgb(255, 247, 237)
    }
    $adminBadge.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
    $adminBadge.AutoSize = $true
    $adminBadge.Location = New-Object System.Drawing.Point(800, 20)
    $adminBadge.Anchor = "Top, Right"
    $headerBar.Controls.Add($adminBadge)

    $mainContent.Controls.Add($headerBar)

    # ========== DASHBOARD PANEL ==========
    $script:DashboardPanel = New-Object System.Windows.Forms.Panel
    $script:DashboardPanel.Location = New-Object System.Drawing.Point(24, 70)
    $script:DashboardPanel.Size = New-Object System.Drawing.Size(820, 520)
    $script:DashboardPanel.Anchor = "Top, Left, Right, Bottom"
    $script:DashboardPanel.BackColor = $script:Colors.Background
    $script:DashboardPanel.Visible = $true

    # Status cards row
    $cardsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $cardsPanel.Location = New-Object System.Drawing.Point(0, 0)
    $cardsPanel.Size = New-Object System.Drawing.Size(820, 110)
    $cardsPanel.BackColor = $script:Colors.Background

    # Service Status Card
    $serviceCard = New-StatusCard -Title "Services" -Value "Ready" -Subtitle "WSUS, SQL, IIS" -Color $script:Colors.Primary
    $cardsPanel.Controls.Add($serviceCard)

    # Database Card
    $dbCard = New-StatusCard -Title "Database" -Value "SUSDB" -Subtitle "SQL Express" -Color $script:Colors.Success
    $cardsPanel.Controls.Add($dbCard)

    # Disk Space Card
    $diskCard = New-StatusCard -Title "Content Path" -Value "C:\WSUS" -Subtitle "Update storage" -Color $script:Colors.Warning
    $cardsPanel.Controls.Add($diskCard)

    $script:DashboardPanel.Controls.Add($cardsPanel)

    # Quick Actions section
    $actionsLabel = New-Object System.Windows.Forms.Label
    $actionsLabel.Text = "Quick Actions"
    $actionsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $actionsLabel.ForeColor = $script:Colors.TextPrimary
    $actionsLabel.Location = New-Object System.Drawing.Point(0, 125)
    $actionsLabel.AutoSize = $true
    $script:DashboardPanel.Controls.Add($actionsLabel)

    $quickActionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $quickActionsPanel.Location = New-Object System.Drawing.Point(0, 155)
    $quickActionsPanel.Size = New-Object System.Drawing.Size(820, 60)
    $quickActionsPanel.BackColor = $script:Colors.Background

    $healthBtn = New-RoundedButton -Text "Run Health Check" -BackColor $script:Colors.Primary -ForeColor $script:Colors.TextLight `
        -Size (New-Object System.Drawing.Size(150, 40)) -Location (New-Object System.Drawing.Point(0, 0)) `
        -OnClick { Start-Operation -OperationId "health" }
    $quickActionsPanel.Controls.Add($healthBtn)

    $cleanupBtn = New-RoundedButton -Text "Deep Cleanup" -BackColor $script:Colors.Surface -ForeColor $script:Colors.TextPrimary `
        -Size (New-Object System.Drawing.Size(130, 40)) -Location (New-Object System.Drawing.Point(160, 0)) `
        -OnClick { Start-Operation -OperationId "cleanup" }
    $cleanupBtn.FlatAppearance.BorderSize = 1
    $cleanupBtn.FlatAppearance.BorderColor = $script:Colors.Border
    $quickActionsPanel.Controls.Add($cleanupBtn)

    $maintenanceBtn = New-RoundedButton -Text "Maintenance" -BackColor $script:Colors.Surface -ForeColor $script:Colors.TextPrimary `
        -Size (New-Object System.Drawing.Size(120, 40)) -Location (New-Object System.Drawing.Point(300, 0)) `
        -OnClick { Start-Operation -OperationId "maintenance" }
    $maintenanceBtn.FlatAppearance.BorderSize = 1
    $maintenanceBtn.FlatAppearance.BorderColor = $script:Colors.Border
    $quickActionsPanel.Controls.Add($maintenanceBtn)

    $script:DashboardPanel.Controls.Add($quickActionsPanel)

    # Configuration info section
    $configLabel = New-Object System.Windows.Forms.Label
    $configLabel.Text = "Configuration"
    $configLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $configLabel.ForeColor = $script:Colors.TextPrimary
    $configLabel.Location = New-Object System.Drawing.Point(0, 230)
    $configLabel.AutoSize = $true
    $script:DashboardPanel.Controls.Add($configLabel)

    $configCard = New-Object System.Windows.Forms.Panel
    $configCard.Location = New-Object System.Drawing.Point(0, 260)
    $configCard.Size = New-Object System.Drawing.Size(400, 150)
    $configCard.BackColor = $script:Colors.Surface

    $configItems = @(
        @{ Label = "Content Path:"; Value = $script:ContentPath },
        @{ Label = "SQL Instance:"; Value = $script:SqlInstance },
        @{ Label = "Export Root:"; Value = $script:ExportRoot },
        @{ Label = "Scripts Path:"; Value = $script:ScriptRoot }
    )

    $yConfigPos = 16
    foreach ($item in $configItems) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $item.Label
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $lbl.ForeColor = $script:Colors.TextSecondary
        $lbl.Location = New-Object System.Drawing.Point(16, $yConfigPos)
        $lbl.Size = New-Object System.Drawing.Size(100, 20)
        $configCard.Controls.Add($lbl)

        $val = New-Object System.Windows.Forms.Label
        $val.Text = $item.Value
        $val.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $val.ForeColor = $script:Colors.TextPrimary
        $val.Location = New-Object System.Drawing.Point(120, $yConfigPos)
        $val.AutoSize = $true
        $configCard.Controls.Add($val)

        $yConfigPos += 28
    }

    $script:DashboardPanel.Controls.Add($configCard)

    $mainContent.Controls.Add($script:DashboardPanel)

    # ========== OPERATION PANEL ==========
    $script:OperationPanel = New-Object System.Windows.Forms.Panel
    $script:OperationPanel.Location = New-Object System.Drawing.Point(24, 70)
    $script:OperationPanel.Size = New-Object System.Drawing.Size(820, 520)
    $script:OperationPanel.Anchor = "Top, Left, Right, Bottom"
    $script:OperationPanel.BackColor = $script:Colors.Background
    $script:OperationPanel.Visible = $false

    # Console output card
    $consoleCard = New-Object System.Windows.Forms.Panel
    $consoleCard.Location = New-Object System.Drawing.Point(0, 0)
    $consoleCard.Size = New-Object System.Drawing.Size(820, 420)
    $consoleCard.Anchor = "Top, Left, Right, Bottom"
    $consoleCard.BackColor = $script:Colors.Surface

    $consoleHeader = New-Object System.Windows.Forms.Panel
    $consoleHeader.Dock = "Top"
    $consoleHeader.Height = 45
    $consoleHeader.BackColor = $script:Colors.ConsoleBackground

    $consoleTitle = New-Object System.Windows.Forms.Label
    $consoleTitle.Text = "Output"
    $consoleTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $consoleTitle.ForeColor = $script:Colors.TextLight
    $consoleTitle.Location = New-Object System.Drawing.Point(16, 12)
    $consoleTitle.AutoSize = $true
    $consoleHeader.Controls.Add($consoleTitle)

    # Clear button
    $clearBtn = New-Object System.Windows.Forms.Button
    $clearBtn.Text = "Clear"
    $clearBtn.Size = New-Object System.Drawing.Size(60, 25)
    $clearBtn.Location = New-Object System.Drawing.Point(740, 10)
    $clearBtn.Anchor = "Top, Right"
    $clearBtn.FlatStyle = "Flat"
    $clearBtn.FlatAppearance.BorderSize = 0
    $clearBtn.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
    $clearBtn.ForeColor = $script:Colors.TextLight
    $clearBtn.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $clearBtn.Cursor = "Hand"
    $clearBtn.Add_Click({ $script:OutputBox.Clear() })
    $consoleHeader.Controls.Add($clearBtn)

    $consoleCard.Controls.Add($consoleHeader)

    $script:OutputBox = New-Object System.Windows.Forms.RichTextBox
    $script:OutputBox.Dock = "Fill"
    $script:OutputBox.BackColor = $script:Colors.ConsoleBackground
    $script:OutputBox.ForeColor = $script:Colors.ConsoleText
    $script:OutputBox.Font = New-Object System.Drawing.Font("Cascadia Code, Consolas", 10)
    $script:OutputBox.ReadOnly = $true
    $script:OutputBox.BorderStyle = "None"
    $script:OutputBox.Padding = New-Object System.Windows.Forms.Padding(16)
    $consoleCard.Controls.Add($script:OutputBox)

    $script:OperationPanel.Controls.Add($consoleCard)

    # Input panel (hidden by default)
    $script:InputPanel = New-Object System.Windows.Forms.Panel
    $script:InputPanel.Location = New-Object System.Drawing.Point(0, 430)
    $script:InputPanel.Size = New-Object System.Drawing.Size(820, 50)
    $script:InputPanel.Anchor = "Bottom, Left, Right"
    $script:InputPanel.BackColor = $script:Colors.Surface
    $script:InputPanel.Visible = $false

    $inputLabel = New-Object System.Windows.Forms.Label
    $inputLabel.Text = "Input Required:"
    $inputLabel.ForeColor = $script:Colors.Warning
    $inputLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $inputLabel.Location = New-Object System.Drawing.Point(16, 15)
    $inputLabel.AutoSize = $true
    $script:InputPanel.Controls.Add($inputLabel)

    $script:InputBox = New-Object System.Windows.Forms.TextBox
    $script:InputBox.Location = New-Object System.Drawing.Point(130, 11)
    $script:InputBox.Size = New-Object System.Drawing.Size(580, 28)
    $script:InputBox.Anchor = "Top, Left, Right"
    $script:InputBox.BackColor = $script:Colors.Background
    $script:InputBox.ForeColor = $script:Colors.TextPrimary
    $script:InputBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $script:InputBox.BorderStyle = "FixedSingle"
    $script:InputPanel.Controls.Add($script:InputBox)

    $sendBtn = New-RoundedButton -Text "Send" -BackColor $script:Colors.Primary -ForeColor $script:Colors.TextLight `
        -Size (New-Object System.Drawing.Size(80, 30)) -Location (New-Object System.Drawing.Point(720, 10)) `
        -OnClick { Send-Input }
    $sendBtn.Anchor = "Top, Right"
    $script:InputPanel.Controls.Add($sendBtn)

    $script:InputBox.Add_KeyDown({
        if ($_.KeyCode -eq "Enter") {
            Send-Input
            $_.SuppressKeyPress = $true
        }
    })

    $script:OperationPanel.Controls.Add($script:InputPanel)

    # Action buttons row
    $actionBar = New-Object System.Windows.Forms.Panel
    $actionBar.Location = New-Object System.Drawing.Point(0, 485)
    $actionBar.Size = New-Object System.Drawing.Size(820, 45)
    $actionBar.Anchor = "Bottom, Left, Right"
    $actionBar.BackColor = $script:Colors.Background

    $script:CancelBtn = New-RoundedButton -Text "Cancel Operation" -BackColor $script:Colors.Danger -ForeColor $script:Colors.TextLight `
        -Size (New-Object System.Drawing.Size(140, 36)) -Location (New-Object System.Drawing.Point(0, 4)) `
        -OnClick { Stop-CurrentOperation }
    $script:CancelBtn.Visible = $false
    $actionBar.Controls.Add($script:CancelBtn)

    $backBtn = New-RoundedButton -Text "Back to Dashboard" -BackColor $script:Colors.Surface -ForeColor $script:Colors.TextPrimary `
        -Size (New-Object System.Drawing.Size(150, 36)) -Location (New-Object System.Drawing.Point(670, 4)) `
        -OnClick { Show-Dashboard }
    $backBtn.Anchor = "Top, Right"
    $backBtn.FlatAppearance.BorderSize = 1
    $backBtn.FlatAppearance.BorderColor = $script:Colors.Border
    $actionBar.Controls.Add($backBtn)

    $script:OperationPanel.Controls.Add($actionBar)

    $mainContent.Controls.Add($script:OperationPanel)

    $form.Controls.Add($mainContent)

    # ========== STATUS BAR ==========
    $statusBar = New-Object System.Windows.Forms.Panel
    $statusBar.Dock = "Bottom"
    $statusBar.Height = 32
    $statusBar.BackColor = $script:Colors.Surface

    $divider = New-Object System.Windows.Forms.Panel
    $divider.Dock = "Top"
    $divider.Height = 1
    $divider.BackColor = $script:Colors.Border
    $statusBar.Controls.Add($divider)

    $script:StatusLabel = New-Object System.Windows.Forms.Label
    $script.Text = "Ready"
    $script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:StatusLabel.ForeColor = $script:Colors.TextSecondary
    $script:StatusLabel.Location = New-Object System.Drawing.Point(240, 8)
    $script:StatusLabel.AutoSize = $true
    $statusBar.Controls.Add($script:StatusLabel)

    $script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $script:ProgressBar.Size = New-Object System.Drawing.Size(150, 6)
    $script:ProgressBar.Location = New-Object System.Drawing.Point(900, 12)
    $script:ProgressBar.Anchor = "Top, Right"
    $script:ProgressBar.Style = "Marquee"
    $script:ProgressBar.MarqueeAnimationSpeed = 30
    $script:ProgressBar.Visible = $false
    $statusBar.Controls.Add($script:ProgressBar)

    $form.Controls.Add($statusBar)

    # Cleanup on close
    $form.Add_FormClosing({
        if ($script:NotifyIcon) {
            $script:NotifyIcon.Visible = $false
            $script:NotifyIcon.Dispose()
        }
        Stop-CurrentOperation
    })

    # Select dashboard by default
    Select-NavItem -Id "dashboard"

    return $form
}

function New-StatusCard {
    param(
        [string]$Title,
        [string]$Value,
        [string]$Subtitle,
        [System.Drawing.Color]$Color
    )

    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(190, 95)
    $card.BackColor = $script:Colors.Surface
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)

    # Accent bar at top
    $accent = New-Object System.Windows.Forms.Panel
    $accent.Dock = "Top"
    $accent.Height = 4
    $accent.BackColor = $Color
    $card.Controls.Add($accent)

    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = $Title
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $titleLbl.ForeColor = $script:Colors.TextSecondary
    $titleLbl.Location = New-Object System.Drawing.Point(16, 20)
    $titleLbl.AutoSize = $true
    $card.Controls.Add($titleLbl)

    $valueLbl = New-Object System.Windows.Forms.Label
    $valueLbl.Text = $Value
    $valueLbl.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $valueLbl.ForeColor = $script:Colors.TextPrimary
    $valueLbl.Location = New-Object System.Drawing.Point(16, 42)
    $valueLbl.AutoSize = $true
    $card.Controls.Add($valueLbl)

    $subtitleLbl = New-Object System.Windows.Forms.Label
    $subtitleLbl.Text = $Subtitle
    $subtitleLbl.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $subtitleLbl.ForeColor = $script:Colors.TextMuted
    $subtitleLbl.Location = New-Object System.Drawing.Point(16, 68)
    $subtitleLbl.AutoSize = $true
    $card.Controls.Add($subtitleLbl)

    return $card
}

function Select-NavItem {
    param([string]$Id)

    foreach ($key in $script:NavButtons.Keys) {
        $btn = $script:NavButtons[$key]
        if ($key -eq $Id) {
            $btn.BackColor = $script:Colors.SidebarActive
        } else {
            $btn.BackColor = $script:Colors.Sidebar
        }
    }
}

function Show-Dashboard {
    $script:PageTitle.Text = "Dashboard"
    $script:DashboardPanel.Visible = $true
    $script:OperationPanel.Visible = $false
    Select-NavItem -Id "dashboard"
}

# ============================================================================
# OPERATION EXECUTION
# ============================================================================
$script:CurrentProcess = $null
$script:ProcessOutput = [System.Text.StringBuilder]::new()

function Write-Console {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color = $script:Colors.ConsoleText
    )

    if ($script:OutputBox.InvokeRequired) {
        $script:OutputBox.Invoke([Action]{
            $script:OutputBox.SelectionStart = $script:OutputBox.TextLength
            $script:OutputBox.SelectionColor = $Color
            $script:OutputBox.AppendText($Text)
            $script:OutputBox.ScrollToCaret()
        })
    } else {
        $script:OutputBox.SelectionStart = $script:OutputBox.TextLength
        $script:OutputBox.SelectionColor = $Color
        $script:OutputBox.AppendText($Text)
        $script:OutputBox.ScrollToCaret()
    }
}

function Start-Operation {
    param([string]$OperationId)

    # Check if already running
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        [System.Windows.Forms.MessageBox]::Show(
            "An operation is already running. Please wait or cancel it first.",
            "Operation in Progress",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    # Update page title
    $titles = @{
        "install" = "Install WSUS + SQL Express"
        "restore" = "Restore Database"
        "import" = "Import from Media"
        "export" = "Export to Media"
        "maintenance" = "Monthly Maintenance"
        "cleanup" = "Deep Cleanup"
        "health" = "Health Check"
        "repair" = "Health Check + Repair"
        "reset" = "Reset Content"
    }
    $script:PageTitle.Text = $titles[$OperationId]

    # Show operation panel
    $script:DashboardPanel.Visible = $false
    $script:OperationPanel.Visible = $true

    # Clear output
    $script:OutputBox.Clear()
    $script:ProcessOutput.Clear()

    # Build command
    $scriptPath = Join-Path $script:ScriptRoot "Invoke-WsusManagement.ps1"

    $command = switch ($OperationId) {
        "install"     { "& '$script:ScriptRoot\Scripts\Install-WsusWithSqlExpress.ps1'" }
        "restore"     { "& '$scriptPath' -Restore -ContentPath '$script:ContentPath' -SqlInstance '$script:SqlInstance'" }
        "import"      { "& '$scriptPath' -ContentPath '$script:ContentPath' -ExportRoot '$script:ExportRoot'" }
        "export"      { "& '$scriptPath' -ContentPath '$script:ContentPath' -ExportRoot '$script:ExportRoot'" }
        "maintenance" { "& '$script:ScriptRoot\Scripts\Invoke-WsusMonthlyMaintenance.ps1'" }
        "cleanup"     { "& '$scriptPath' -Cleanup -Force -SqlInstance '$script:SqlInstance'" }
        "health"      { "& '$scriptPath' -Health -ContentPath '$script:ContentPath' -SqlInstance '$script:SqlInstance'" }
        "repair"      { "& '$scriptPath' -Repair -ContentPath '$script:ContentPath' -SqlInstance '$script:SqlInstance'" }
        "reset"       { "& '$scriptPath' -Reset" }
        default       { "Write-Host 'Unknown operation: $OperationId'" }
    }

    Write-Console "Starting: $($titles[$OperationId])`n" -Color $script:Colors.Primary
    Write-Console "Command: $command`n`n" -Color $script:Colors.TextMuted
    Write-GuiLog "Starting operation: $OperationId"

    # Update UI state
    $script:StatusLabel.Text = "Running: $($titles[$OperationId])"
    $script:ProgressBar.Visible = $true
    $script:CancelBtn.Visible = $true

    # Disable nav buttons
    foreach ($btn in $script:NavButtons.Values) {
        $btn.Enabled = $false
    }

    # Start process
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $script:ScriptRoot

    $script:CurrentProcess = New-Object System.Diagnostics.Process
    $script:CurrentProcess.StartInfo = $psi
    $script:CurrentProcess.EnableRaisingEvents = $true

    # Output handler
    $outputHandler = {
        $data = $Event.SourceEventArgs.Data
        if ($data) {
            $script:ProcessOutput.AppendLine($data)

            # Check for input prompts
            $inputPatterns = @('\?\s*$', '\(Y/n\)\s*$', '\(yes/no\)\s*$', 'Select.*:\s*$', 'Enter.*:\s*$', 'Press.*key', '\[.*\]:\s*$')
            $needsInput = $false
            foreach ($pattern in $inputPatterns) {
                if ($data -match $pattern) {
                    $needsInput = $true
                    break
                }
            }

            if ($needsInput) {
                if ($script:Form.InvokeRequired) {
                    $script:Form.Invoke([Action]{
                        $script:InputPanel.Visible = $true
                        $script:InputBox.Focus()
                    })
                } else {
                    $script:InputPanel.Visible = $true
                    $script:InputBox.Focus()
                }
                Show-Notification "Input Required" $data "Warning"
            }

            # Determine output color
            $color = $script:Colors.ConsoleText
            if ($data -match 'ERROR|FAIL|Exception') {
                $color = $script:Colors.Danger
            } elseif ($data -match 'WARN|Warning') {
                $color = $script:Colors.Warning
            } elseif ($data -match 'OK|Success|Complete') {
                $color = $script:Colors.Success
            } elseif ($data -match '===') {
                $color = $script:Colors.Primary
            }

            Write-Console "$data`n" -Color $color
        }
    }

    $errorHandler = {
        $data = $Event.SourceEventArgs.Data
        if ($data) {
            Write-Console "$data`n" -Color $script:Colors.Danger
        }
    }

    $exitHandler = {
        $exitCode = $script:CurrentProcess.ExitCode

        if ($script:Form.InvokeRequired) {
            $script:Form.Invoke([Action]{
                $script:StatusLabel.Text = "Completed (Exit: $exitCode)"
                $script:ProgressBar.Visible = $false
                $script:CancelBtn.Visible = $false
                $script:InputPanel.Visible = $false

                foreach ($btn in $script:NavButtons.Values) {
                    $btn.Enabled = $true
                }
            })
        } else {
            $script:StatusLabel.Text = "Completed (Exit: $exitCode)"
            $script:ProgressBar.Visible = $false
            $script:CancelBtn.Visible = $false
            $script:InputPanel.Visible = $false

            foreach ($btn in $script:NavButtons.Values) {
                $btn.Enabled = $true
            }
        }

        Write-Console "`n=== Operation completed (Exit code: $exitCode) ===`n" -Color $script:Colors.Primary
        Write-GuiLog "Operation completed with exit code: $exitCode"

        if ($exitCode -eq 0) {
            Show-Notification "Operation Complete" "The operation finished successfully." "Info"
        }
    }

    Register-ObjectEvent -InputObject $script:CurrentProcess -EventName OutputDataReceived -Action $outputHandler | Out-Null
    Register-ObjectEvent -InputObject $script:CurrentProcess -EventName ErrorDataReceived -Action $errorHandler | Out-Null
    Register-ObjectEvent -InputObject $script:CurrentProcess -EventName Exited -Action $exitHandler | Out-Null

    $script:CurrentProcess.Start() | Out-Null
    $script:CurrentProcess.BeginOutputReadLine()
    $script:CurrentProcess.BeginErrorReadLine()
}

function Send-Input {
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $userInput = $script:InputBox.Text
        Write-Console "> $userInput`n" -Color $script:Colors.Warning
        $script:CurrentProcess.StandardInput.WriteLine($userInput)
        $script:InputBox.Clear()
        $script:InputPanel.Visible = $false
        Write-GuiLog "User input sent: $userInput"
    }
}

function Stop-CurrentOperation {
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $script:CurrentProcess.Kill()
        Write-Console "`n=== Operation cancelled by user ===`n" -Color $script:Colors.Warning
        Write-GuiLog "Operation cancelled by user"
    }

    $script:StatusLabel.Text = "Cancelled"
    $script:ProgressBar.Visible = $false
    $script:CancelBtn.Visible = $false
    $script:InputPanel.Visible = $false

    foreach ($btn in $script:NavButtons.Values) {
        $btn.Enabled = $true
    }
}

# ============================================================================
# SETTINGS DIALOG
# ============================================================================
function Show-SettingsDialog {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Settings"
    $dialog.Size = New-Object System.Drawing.Size(520, 380)
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $script:Colors.Background
    $dialog.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # Title
    $titleLbl = New-Object System.Windows.Forms.Label
    $titleLbl.Text = "Configuration Settings"
    $titleLbl.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $titleLbl.ForeColor = $script:Colors.TextPrimary
    $titleLbl.Location = New-Object System.Drawing.Point(24, 20)
    $titleLbl.AutoSize = $true
    $dialog.Controls.Add($titleLbl)

    $yPos = 60

    # Content Path
    $lblContent = New-Object System.Windows.Forms.Label
    $lblContent.Text = "WSUS Content Path"
    $lblContent.ForeColor = $script:Colors.TextSecondary
    $lblContent.Location = New-Object System.Drawing.Point(24, $yPos)
    $lblContent.AutoSize = $true
    $dialog.Controls.Add($lblContent)
    $yPos += 22

    $txtContent = New-Object System.Windows.Forms.TextBox
    $txtContent.Text = $script:ContentPath
    $txtContent.Location = New-Object System.Drawing.Point(24, $yPos)
    $txtContent.Size = New-Object System.Drawing.Size(360, 28)
    $txtContent.BackColor = $script:Colors.Surface
    $txtContent.ForeColor = $script:Colors.TextPrimary
    $txtContent.BorderStyle = "FixedSingle"
    $dialog.Controls.Add($txtContent)

    $btnBrowseContent = New-RoundedButton -Text "Browse" -BackColor $script:Colors.Surface -ForeColor $script:Colors.TextPrimary `
        -Size (New-Object System.Drawing.Size(80, 28)) -Location (New-Object System.Drawing.Point(394, $yPos)) `
        -OnClick {
            $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fbd.SelectedPath = $txtContent.Text
            if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtContent.Text = $fbd.SelectedPath
            }
        }
    $btnBrowseContent.FlatAppearance.BorderSize = 1
    $btnBrowseContent.FlatAppearance.BorderColor = $script:Colors.Border
    $dialog.Controls.Add($btnBrowseContent)
    $yPos += 50

    # SQL Instance
    $lblSql = New-Object System.Windows.Forms.Label
    $lblSql.Text = "SQL Instance"
    $lblSql.ForeColor = $script:Colors.TextSecondary
    $lblSql.Location = New-Object System.Drawing.Point(24, $yPos)
    $lblSql.AutoSize = $true
    $dialog.Controls.Add($lblSql)
    $yPos += 22

    $txtSql = New-Object System.Windows.Forms.TextBox
    $txtSql.Text = $script:SqlInstance
    $txtSql.Location = New-Object System.Drawing.Point(24, $yPos)
    $txtSql.Size = New-Object System.Drawing.Size(450, 28)
    $txtSql.BackColor = $script:Colors.Surface
    $txtSql.ForeColor = $script:Colors.TextPrimary
    $txtSql.BorderStyle = "FixedSingle"
    $dialog.Controls.Add($txtSql)
    $yPos += 50

    # Export Root
    $lblExport = New-Object System.Windows.Forms.Label
    $lblExport.Text = "Export/Import Root Path"
    $lblExport.ForeColor = $script:Colors.TextSecondary
    $lblExport.Location = New-Object System.Drawing.Point(24, $yPos)
    $lblExport.AutoSize = $true
    $dialog.Controls.Add($lblExport)
    $yPos += 22

    $txtExport = New-Object System.Windows.Forms.TextBox
    $txtExport.Text = $script:ExportRoot
    $txtExport.Location = New-Object System.Drawing.Point(24, $yPos)
    $txtExport.Size = New-Object System.Drawing.Size(360, 28)
    $txtExport.BackColor = $script:Colors.Surface
    $txtExport.ForeColor = $script:Colors.TextPrimary
    $txtExport.BorderStyle = "FixedSingle"
    $dialog.Controls.Add($txtExport)

    $btnBrowseExport = New-RoundedButton -Text "Browse" -BackColor $script:Colors.Surface -ForeColor $script:Colors.TextPrimary `
        -Size (New-Object System.Drawing.Size(80, 28)) -Location (New-Object System.Drawing.Point(394, $yPos)) `
        -OnClick {
            $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fbd.SelectedPath = $txtExport.Text
            if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $txtExport.Text = $fbd.SelectedPath
            }
        }
    $btnBrowseExport.FlatAppearance.BorderSize = 1
    $btnBrowseExport.FlatAppearance.BorderColor = $script:Colors.Border
    $dialog.Controls.Add($btnBrowseExport)
    $yPos += 60

    # Buttons
    $btnSave = New-RoundedButton -Text "Save Changes" -BackColor $script:Colors.Primary -ForeColor $script:Colors.TextLight `
        -Size (New-Object System.Drawing.Size(120, 36)) -Location (New-Object System.Drawing.Point(270, $yPos)) `
        -OnClick {
            $script:ContentPath = $txtContent.Text
            $script:SqlInstance = $txtSql.Text
            $script:ExportRoot = $txtExport.Text

            Write-Console "`nSettings updated:`n" -Color $script:Colors.Primary
            Write-Console "  Content: $script:ContentPath`n" -Color $script:Colors.TextMuted
            Write-Console "  SQL: $script:SqlInstance`n" -Color $script:Colors.TextMuted
            Write-Console "  Export: $script:ExportRoot`n`n" -Color $script:Colors.TextMuted

            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        }
    $dialog.Controls.Add($btnSave)

    $btnCancel = New-RoundedButton -Text "Cancel" -BackColor $script:Colors.Surface -ForeColor $script:Colors.TextPrimary `
        -Size (New-Object System.Drawing.Size(90, 36)) -Location (New-Object System.Drawing.Point(400, $yPos)) `
        -OnClick {
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $dialog.Close()
        }
    $btnCancel.FlatAppearance.BorderSize = 1
    $btnCancel.FlatAppearance.BorderColor = $script:Colors.Border
    $dialog.Controls.Add($btnCancel)

    $dialog.ShowDialog() | Out-Null
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================
$script:Form = New-WsusGui

# Initial welcome message
Write-Console "WSUS Manager Ready`n" -Color $script:Colors.Primary
Write-Console "Select an operation from the sidebar to begin.`n`n" -Color $script:Colors.ConsoleText

# Check admin rights
if (-not (Test-IsAdmin)) {
    Write-Console "WARNING: Not running as Administrator!`n" -Color $script:Colors.Warning
    Write-Console "Some operations may fail. Right-click and 'Run as Administrator' for full functionality.`n`n" -Color $script:Colors.Warning
}

[System.Windows.Forms.Application]::Run($script:Form)

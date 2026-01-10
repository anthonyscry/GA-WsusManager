#Requires -Version 5.1
<#
===============================================================================
Script: WsusManagementGui.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.0
Date: 2026-01-10
===============================================================================
.SYNOPSIS
    Windows Forms GUI for WSUS Management operations.

.DESCRIPTION
    Provides a graphical interface for all WSUS management tasks including:
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
# HELPER FUNCTIONS
# ============================================================================
function Write-GuiLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    # Append to log file
    if ($script:LogPath) {
        $logDir = Split-Path $script:LogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Add-Content -Path $script:LogPath -Value $logEntry -ErrorAction SilentlyContinue
    }
}

function Show-Alert {
    param([string]$Title, [string]$Message)

    # Flash window and play sound
    [System.Media.SystemSounds]::Exclamation.Play()

    # Show balloon notification if possible
    if ($script:NotifyIcon) {
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Message
        $script:NotifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
        $script:NotifyIcon.ShowBalloonTip(5000)
    }

    Write-GuiLog "$Title - $Message" "ALERT"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ============================================================================
# MAIN FORM DESIGN
# ============================================================================
function New-WsusGui {
    # Create main form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WSUS Management v3.2.0 - GUI"
    $form.Size = New-Object System.Drawing.Size(900, 700)
    $form.StartPosition = "CenterScreen"
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false

    # Create system tray icon for notifications
    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $script:NotifyIcon.Text = "WSUS Management"
    $script:NotifyIcon.Visible = $true

    # Header Panel
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 80
    $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "WSUS Management"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::White
    $titleLabel.AutoSize = $true
    $titleLabel.Location = New-Object System.Drawing.Point(20, 15)
    $headerPanel.Controls.Add($titleLabel)

    $subtitleLabel = New-Object System.Windows.Forms.Label
    $subtitleLabel.Text = "Author: Tony Tran, ISSO, GA-ASI"
    $subtitleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $subtitleLabel.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $subtitleLabel.AutoSize = $true
    $subtitleLabel.Location = New-Object System.Drawing.Point(22, 50)
    $headerPanel.Controls.Add($subtitleLabel)

    # Admin status indicator
    $adminLabel = New-Object System.Windows.Forms.Label
    $isAdmin = Test-IsAdmin
    $adminLabel.Text = if ($isAdmin) { "Running as Administrator" } else { "NOT ADMIN - Some features disabled" }
    $adminLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $adminLabel.ForeColor = if ($isAdmin) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::Orange }
    $adminLabel.AutoSize = $true
    $adminLabel.Location = New-Object System.Drawing.Point(500, 50)
    $headerPanel.Controls.Add($adminLabel)

    # Settings button
    $settingsBtn = New-Object System.Windows.Forms.Button
    $settingsBtn.Text = "Settings"
    $settingsBtn.Size = New-Object System.Drawing.Size(80, 28)
    $settingsBtn.Location = New-Object System.Drawing.Point(790, 45)
    $settingsBtn.FlatStyle = "Flat"
    $settingsBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 90, 170)
    $settingsBtn.ForeColor = [System.Drawing.Color]::White
    $settingsBtn.Add_Click({ Show-SettingsDialog })
    $headerPanel.Controls.Add($settingsBtn)

    $form.Controls.Add($headerPanel)

    # Left Panel - Operations
    $leftPanel = New-Object System.Windows.Forms.Panel
    $leftPanel.Location = New-Object System.Drawing.Point(10, 90)
    $leftPanel.Size = New-Object System.Drawing.Size(250, 560)
    $leftPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

    # Operation categories
    $operations = @(
        @{ Category = "INSTALLATION"; Items = @(
            @{ Name = "Install WSUS + SQL Express"; Id = "install" }
        )},
        @{ Category = "DATABASE"; Items = @(
            @{ Name = "Restore Database"; Id = "restore" },
            @{ Name = "Import from Media"; Id = "import" },
            @{ Name = "Export to Media"; Id = "export" }
        )},
        @{ Category = "MAINTENANCE"; Items = @(
            @{ Name = "Monthly Maintenance"; Id = "maintenance" },
            @{ Name = "Deep Cleanup"; Id = "cleanup" }
        )},
        @{ Category = "TROUBLESHOOTING"; Items = @(
            @{ Name = "Health Check"; Id = "health" },
            @{ Name = "Health Check + Repair"; Id = "repair" },
            @{ Name = "Reset Content"; Id = "reset" }
        )},
        @{ Category = "CLIENT"; Items = @(
            @{ Name = "Force Client Check-In"; Id = "client" }
        )}
    )

    $yPos = 10
    $script:OperationButtons = @{}

    foreach ($category in $operations) {
        # Category label
        $catLabel = New-Object System.Windows.Forms.Label
        $catLabel.Text = $category.Category
        $catLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $catLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
        $catLabel.Location = New-Object System.Drawing.Point(10, $yPos)
        $catLabel.AutoSize = $true
        $leftPanel.Controls.Add($catLabel)
        $yPos += 25

        foreach ($item in $category.Items) {
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = $item.Name
            $btn.Size = New-Object System.Drawing.Size(230, 35)
            $btn.Location = New-Object System.Drawing.Point(10, $yPos)
            $btn.FlatStyle = "Flat"
            $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
            $btn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
            $btn.ForeColor = [System.Drawing.Color]::White
            $btn.TextAlign = "MiddleLeft"
            $btn.Cursor = "Hand"
            $btn.Tag = $item.Id

            # Hover effect
            $btn.Add_MouseEnter({ $this.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215) })
            $btn.Add_MouseLeave({ $this.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60) })

            # Click handler
            $btn.Add_Click({
                $operationId = $this.Tag
                Start-Operation -OperationId $operationId
            })

            $leftPanel.Controls.Add($btn)
            $script:OperationButtons[$item.Id] = $btn
            $yPos += 40
        }
        $yPos += 10
    }

    $form.Controls.Add($leftPanel)

    # Right Panel - Output Console
    $rightPanel = New-Object System.Windows.Forms.Panel
    $rightPanel.Location = New-Object System.Drawing.Point(270, 90)
    $rightPanel.Size = New-Object System.Drawing.Size(610, 510)
    $rightPanel.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)

    # Output label
    $outputLabel = New-Object System.Windows.Forms.Label
    $outputLabel.Text = "Output Console"
    $outputLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $outputLabel.ForeColor = [System.Drawing.Color]::White
    $outputLabel.Location = New-Object System.Drawing.Point(10, 5)
    $outputLabel.AutoSize = $true
    $rightPanel.Controls.Add($outputLabel)

    # Output textbox
    $script:OutputBox = New-Object System.Windows.Forms.RichTextBox
    $script:OutputBox.Location = New-Object System.Drawing.Point(10, 30)
    $script:OutputBox.Size = New-Object System.Drawing.Size(590, 420)
    $script:OutputBox.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
    $script:OutputBox.ForeColor = [System.Drawing.Color]::LightGreen
    $script:OutputBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    $script:OutputBox.ReadOnly = $true
    $script:OutputBox.ScrollBars = "Vertical"
    $script:OutputBox.BorderStyle = "None"
    $rightPanel.Controls.Add($script:OutputBox)

    # Input panel (initially hidden)
    $script:InputPanel = New-Object System.Windows.Forms.Panel
    $script:InputPanel.Location = New-Object System.Drawing.Point(10, 455)
    $script:InputPanel.Size = New-Object System.Drawing.Size(590, 45)
    $script:InputPanel.Visible = $false

    $inputLabel = New-Object System.Windows.Forms.Label
    $inputLabel.Text = "Input Required:"
    $inputLabel.ForeColor = [System.Drawing.Color]::Yellow
    $inputLabel.Location = New-Object System.Drawing.Point(0, 12)
    $inputLabel.AutoSize = $true
    $script:InputPanel.Controls.Add($inputLabel)

    $script:InputBox = New-Object System.Windows.Forms.TextBox
    $script:InputBox.Location = New-Object System.Drawing.Point(100, 8)
    $script:InputBox.Size = New-Object System.Drawing.Size(400, 25)
    $script:InputBox.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $script:InputBox.ForeColor = [System.Drawing.Color]::White
    $script:InputBox.BorderStyle = "FixedSingle"
    $script:InputPanel.Controls.Add($script:InputBox)

    $sendBtn = New-Object System.Windows.Forms.Button
    $sendBtn.Text = "Send"
    $sendBtn.Size = New-Object System.Drawing.Size(70, 27)
    $sendBtn.Location = New-Object System.Drawing.Point(510, 7)
    $sendBtn.FlatStyle = "Flat"
    $sendBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $sendBtn.ForeColor = [System.Drawing.Color]::White
    $sendBtn.Add_Click({
        Send-Input
    })
    $script:InputPanel.Controls.Add($sendBtn)

    # Enter key sends input
    $script:InputBox.Add_KeyDown({
        if ($_.KeyCode -eq "Enter") {
            Send-Input
            $_.SuppressKeyPress = $true
        }
    })

    $rightPanel.Controls.Add($script:InputPanel)
    $form.Controls.Add($rightPanel)

    # Bottom status bar
    $statusBar = New-Object System.Windows.Forms.StatusStrip
    $statusBar.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)

    $script:StatusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $script:StatusLabel.Text = "Ready"
    $script:StatusLabel.ForeColor = [System.Drawing.Color]::White
    $statusBar.Items.Add($script:StatusLabel)

    $script:ProgressBar = New-Object System.Windows.Forms.ToolStripProgressBar
    $script:ProgressBar.Style = "Marquee"
    $script:ProgressBar.Visible = $false
    $statusBar.Items.Add($script:ProgressBar)

    # Cancel button in status bar
    $script:CancelButton = New-Object System.Windows.Forms.ToolStripButton
    $script:CancelButton.Text = "Cancel"
    $script:CancelButton.ForeColor = [System.Drawing.Color]::White
    $script:CancelButton.Visible = $false
    $script:CancelButton.Add_Click({
        Stop-CurrentOperation
    })
    $statusBar.Items.Add($script:CancelButton)

    $form.Controls.Add($statusBar)

    # Cleanup on close
    $form.Add_FormClosing({
        if ($script:NotifyIcon) {
            $script:NotifyIcon.Visible = $false
            $script:NotifyIcon.Dispose()
        }
        Stop-CurrentOperation
    })

    return $form
}

# ============================================================================
# OPERATION EXECUTION
# ============================================================================
$script:CurrentProcess = $null
$script:ProcessOutput = [System.Text.StringBuilder]::new()

function Write-Output-Text {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::LightGreen
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

    # Check if operation is already running
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        [System.Windows.Forms.MessageBox]::Show(
            "An operation is already running. Please wait or cancel it first.",
            "Operation in Progress",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    # Clear output
    $script:OutputBox.Clear()
    $script:ProcessOutput.Clear()

    # Build command based on operation
    $scriptPath = Join-Path $script:ScriptRoot "Invoke-WsusManagement.ps1"

    $command = switch ($OperationId) {
        "install"     { "& '$script:ScriptRoot\Scripts\Install-WsusWithSqlExpress.ps1'" }
        "restore"     { "& '$scriptPath' -Restore -ContentPath '$script:ContentPath' -SqlInstance '$script:SqlInstance'" }
        "import"      { "& '$scriptPath' -ContentPath '$script:ContentPath' -ExportRoot '$script:ExportRoot'" }  # Will need menu interaction
        "export"      { "& '$scriptPath' -ContentPath '$script:ContentPath' -ExportRoot '$script:ExportRoot'" }
        "maintenance" { "& '$script:ScriptRoot\Scripts\Invoke-WsusMonthlyMaintenance.ps1'" }
        "cleanup"     { "& '$scriptPath' -Cleanup -Force -SqlInstance '$script:SqlInstance'" }
        "health"      { "& '$scriptPath' -Health -ContentPath '$script:ContentPath' -SqlInstance '$script:SqlInstance'" }
        "repair"      { "& '$scriptPath' -Repair -ContentPath '$script:ContentPath' -SqlInstance '$script:SqlInstance'" }
        "reset"       { "& '$scriptPath' -Reset" }
        "client"      { "& '$script:ScriptRoot\Scripts\Invoke-WsusClientCheckIn.ps1'" }
        default       { "Write-Host 'Unknown operation: $OperationId'" }
    }

    Write-Output-Text "Starting: $OperationId`n" -Color ([System.Drawing.Color]::Cyan)
    Write-Output-Text "Command: $command`n`n" -Color ([System.Drawing.Color]::Gray)
    Write-GuiLog "Starting operation: $OperationId"

    # Update UI
    $script:StatusLabel.Text = "Running: $OperationId"
    $script:ProgressBar.Visible = $true
    $script:CancelButton.Visible = $true

    # Disable operation buttons
    foreach ($btn in $script:OperationButtons.Values) {
        $btn.Enabled = $false
    }

    # Start PowerShell process
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

    # Output handlers
    $outputHandler = {
        $data = $Event.SourceEventArgs.Data
        if ($data) {
            $script:ProcessOutput.AppendLine($data)

            # Check for input prompts
            $inputPatterns = @(
                '\?\s*$',
                '\(Y/n\)\s*$',
                '\(yes/no\)\s*$',
                'Select.*:\s*$',
                'Enter.*:\s*$',
                'Press.*key',
                '\[.*\]:\s*$'
            )

            $needsInput = $false
            foreach ($pattern in $inputPatterns) {
                if ($data -match $pattern) {
                    $needsInput = $true
                    break
                }
            }

            if ($needsInput) {
                # Show input panel and alert
                if ($script:Form.InvokeRequired) {
                    $script:Form.Invoke([Action]{
                        $script:InputPanel.Visible = $true
                        $script:InputBox.Focus()
                    })
                } else {
                    $script:InputPanel.Visible = $true
                    $script:InputBox.Focus()
                }
                Show-Alert "Input Required" $data
            }

            # Determine color based on content
            $color = [System.Drawing.Color]::LightGreen
            if ($data -match 'ERROR|FAIL|Exception') {
                $color = [System.Drawing.Color]::Red
            } elseif ($data -match 'WARN|Warning') {
                $color = [System.Drawing.Color]::Yellow
            } elseif ($data -match 'OK|Success|Complete') {
                $color = [System.Drawing.Color]::LightGreen
            } elseif ($data -match '===') {
                $color = [System.Drawing.Color]::Cyan
            }

            Write-Output-Text "$data`n" -Color $color
        }
    }

    $errorHandler = {
        $data = $Event.SourceEventArgs.Data
        if ($data) {
            Write-Output-Text "$data`n" -Color ([System.Drawing.Color]::Red)
        }
    }

    $exitHandler = {
        $exitCode = $script:CurrentProcess.ExitCode

        if ($script:Form.InvokeRequired) {
            $script:Form.Invoke([Action]{
                $script:StatusLabel.Text = "Completed (Exit: $exitCode)"
                $script:ProgressBar.Visible = $false
                $script:CancelButton.Visible = $false
                $script:InputPanel.Visible = $false

                foreach ($btn in $script:OperationButtons.Values) {
                    $btn.Enabled = $true
                }
            })
        } else {
            $script:StatusLabel.Text = "Completed (Exit: $exitCode)"
            $script:ProgressBar.Visible = $false
            $script:CancelButton.Visible = $false
            $script:InputPanel.Visible = $false

            foreach ($btn in $script:OperationButtons.Values) {
                $btn.Enabled = $true
            }
        }

        Write-Output-Text "`n=== Operation completed (Exit code: $exitCode) ===`n" -Color ([System.Drawing.Color]::Cyan)
        Write-GuiLog "Operation completed with exit code: $exitCode"

        if ($exitCode -eq 0) {
            Show-Alert "Operation Complete" "The operation finished successfully."
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
        $input = $script:InputBox.Text
        Write-Output-Text "> $input`n" -Color ([System.Drawing.Color]::Yellow)
        $script:CurrentProcess.StandardInput.WriteLine($input)
        $script:InputBox.Clear()
        $script:InputPanel.Visible = $false
        Write-GuiLog "User input sent: $input"
    }
}

function Stop-CurrentOperation {
    if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
        $script:CurrentProcess.Kill()
        Write-Output-Text "`n=== Operation cancelled by user ===`n" -Color ([System.Drawing.Color]::Orange)
        Write-GuiLog "Operation cancelled by user"
    }

    $script:StatusLabel.Text = "Cancelled"
    $script:ProgressBar.Visible = $false
    $script:CancelButton.Visible = $false
    $script:InputPanel.Visible = $false

    foreach ($btn in $script:OperationButtons.Values) {
        $btn.Enabled = $true
    }
}

# ============================================================================
# SETTINGS DIALOG
# ============================================================================
function Show-SettingsDialog {
    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = "Settings"
    $settingsForm.Size = New-Object System.Drawing.Size(500, 320)
    $settingsForm.StartPosition = "CenterParent"
    $settingsForm.FormBorderStyle = "FixedDialog"
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false
    $settingsForm.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $settingsForm.ForeColor = [System.Drawing.Color]::White

    $yPos = 20

    # Content Path
    $lblContent = New-Object System.Windows.Forms.Label
    $lblContent.Text = "WSUS Content Path:"
    $lblContent.Location = New-Object System.Drawing.Point(20, $yPos)
    $lblContent.AutoSize = $true
    $settingsForm.Controls.Add($lblContent)
    $yPos += 25

    $txtContent = New-Object System.Windows.Forms.TextBox
    $txtContent.Text = $script:ContentPath
    $txtContent.Location = New-Object System.Drawing.Point(20, $yPos)
    $txtContent.Size = New-Object System.Drawing.Size(350, 25)
    $txtContent.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $txtContent.ForeColor = [System.Drawing.Color]::White
    $settingsForm.Controls.Add($txtContent)

    $btnBrowseContent = New-Object System.Windows.Forms.Button
    $btnBrowseContent.Text = "Browse"
    $btnBrowseContent.Location = New-Object System.Drawing.Point(380, ($yPos - 2))
    $btnBrowseContent.Size = New-Object System.Drawing.Size(80, 25)
    $btnBrowseContent.FlatStyle = "Flat"
    $btnBrowseContent.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnBrowseContent.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.SelectedPath = $txtContent.Text
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtContent.Text = $fbd.SelectedPath
        }
    })
    $settingsForm.Controls.Add($btnBrowseContent)
    $yPos += 45

    # SQL Instance
    $lblSql = New-Object System.Windows.Forms.Label
    $lblSql.Text = "SQL Instance:"
    $lblSql.Location = New-Object System.Drawing.Point(20, $yPos)
    $lblSql.AutoSize = $true
    $settingsForm.Controls.Add($lblSql)
    $yPos += 25

    $txtSql = New-Object System.Windows.Forms.TextBox
    $txtSql.Text = $script:SqlInstance
    $txtSql.Location = New-Object System.Drawing.Point(20, $yPos)
    $txtSql.Size = New-Object System.Drawing.Size(440, 25)
    $txtSql.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $txtSql.ForeColor = [System.Drawing.Color]::White
    $settingsForm.Controls.Add($txtSql)
    $yPos += 45

    # Export Root
    $lblExport = New-Object System.Windows.Forms.Label
    $lblExport.Text = "Export/Import Root Path:"
    $lblExport.Location = New-Object System.Drawing.Point(20, $yPos)
    $lblExport.AutoSize = $true
    $settingsForm.Controls.Add($lblExport)
    $yPos += 25

    $txtExport = New-Object System.Windows.Forms.TextBox
    $txtExport.Text = $script:ExportRoot
    $txtExport.Location = New-Object System.Drawing.Point(20, $yPos)
    $txtExport.Size = New-Object System.Drawing.Size(350, 25)
    $txtExport.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $txtExport.ForeColor = [System.Drawing.Color]::White
    $settingsForm.Controls.Add($txtExport)

    $btnBrowseExport = New-Object System.Windows.Forms.Button
    $btnBrowseExport.Text = "Browse"
    $btnBrowseExport.Location = New-Object System.Drawing.Point(380, ($yPos - 2))
    $btnBrowseExport.Size = New-Object System.Drawing.Size(80, 25)
    $btnBrowseExport.FlatStyle = "Flat"
    $btnBrowseExport.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnBrowseExport.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.SelectedPath = $txtExport.Text
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtExport.Text = $fbd.SelectedPath
        }
    })
    $settingsForm.Controls.Add($btnBrowseExport)
    $yPos += 55

    # Buttons
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Location = New-Object System.Drawing.Point(280, $yPos)
    $btnSave.Size = New-Object System.Drawing.Size(90, 30)
    $btnSave.FlatStyle = "Flat"
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnSave.Add_Click({
        $script:ContentPath = $txtContent.Text
        $script:SqlInstance = $txtSql.Text
        $script:ExportRoot = $txtExport.Text

        # Update display
        Write-Output-Text "`nSettings updated:`n" -Color ([System.Drawing.Color]::Cyan)
        Write-Output-Text "  Content: $script:ContentPath`n" -Color ([System.Drawing.Color]::Gray)
        Write-Output-Text "  SQL: $script:SqlInstance`n" -Color ([System.Drawing.Color]::Gray)
        Write-Output-Text "  Export: $script:ExportRoot`n`n" -Color ([System.Drawing.Color]::Gray)

        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $settingsForm.Close()
    })
    $settingsForm.Controls.Add($btnSave)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(380, $yPos)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $btnCancel.Add_Click({
        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $settingsForm.Close()
    })
    $settingsForm.Controls.Add($btnCancel)

    $settingsForm.ShowDialog() | Out-Null
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================
$script:Form = New-WsusGui

# Check for admin rights
if (-not (Test-IsAdmin)) {
    Write-Output-Text "WARNING: Not running as Administrator!`n" -Color ([System.Drawing.Color]::Orange)
    Write-Output-Text "Some operations may fail. Right-click and 'Run as Administrator' for full functionality.`n`n" -Color ([System.Drawing.Color]::Yellow)
}

Write-Output-Text "WSUS Management GUI Ready`n" -Color ([System.Drawing.Color]::Cyan)
Write-Output-Text "Select an operation from the left panel to begin.`n`n" -Color ([System.Drawing.Color]::White)
Write-Output-Text "Paths:`n" -Color ([System.Drawing.Color]::Gray)
Write-Output-Text "  Content: $script:ContentPath`n" -Color ([System.Drawing.Color]::Gray)
Write-Output-Text "  SQL: $script:SqlInstance`n" -Color ([System.Drawing.Color]::Gray)
Write-Output-Text "  Export: $script:ExportRoot`n" -Color ([System.Drawing.Color]::Gray)
Write-Output-Text "  Scripts: $script:ScriptRoot`n`n" -Color ([System.Drawing.Color]::Gray)

[System.Windows.Forms.Application]::Run($script:Form)

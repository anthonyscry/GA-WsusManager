#Requires -Version 5.1
<#
===============================================================================
Module: WsusDialogs.psm1
Purpose: Reusable WPF dialog functions extracted from WsusManagementGui.ps1
===============================================================================
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

#region Show-GrantSysadminDialog
function Show-GrantSysadminDialog {
    param(
        [System.Windows.Window]$OwnerWindow,
        [string]$DefaultLogin,
        [string]$DefaultSqlUser = "sa"
    )

    $result = @{ Cancelled = $true; Login = ""; UseSqlAuth = $false; SqlUser = $DefaultSqlUser; SqlPassword = "" }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Grant SQL Sysadmin"
    $dlg.Width = 520
    $dlg.Height = 380
    $dlg.WindowStartupLocation = "CenterOwner"
    if ($OwnerWindow) { $dlg.Owner = $OwnerWindow }
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Grant SQL Server sysadmin"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,12"
    $stack.Children.Add($title)

    $note = New-Object System.Windows.Controls.TextBlock
    $note.Text = "Enter a Windows user or group (DOMAIN\User or DOMAIN\Group). Uses Windows authentication by default."
    $note.FontSize = 11
    $note.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $note.Margin = "0,0,0,8"
    $stack.Children.Add($note)

    $loginLbl = New-Object System.Windows.Controls.TextBlock
    $loginLbl.Text = "Login to grant:" 
    $loginLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $loginLbl.Margin = "0,0,0,4"
    $stack.Children.Add($loginLbl)

    $loginTxt = New-Object System.Windows.Controls.TextBox
    $loginTxt.Text = $DefaultLogin
    $loginTxt.Margin = "0,0,0,12"
    $loginTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $loginTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $loginTxt.Padding = "6,4"
    $stack.Children.Add($loginTxt)

    $authCheck = New-Object System.Windows.Controls.CheckBox
    $authCheck.Content = "Use SQL authentication (sa) if required"
    $authCheck.Margin = "0,4,0,4"
    $authCheck.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $stack.Children.Add($authCheck)

    $authNote = New-Object System.Windows.Controls.TextBlock
    $authNote.Text = "Only needed if current user is not SQL sysadmin."
    $authNote.FontSize = 10
    $authNote.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $authNote.Margin = "0,0,0,8"
    $stack.Children.Add($authNote)

    $sqlUserLbl = New-Object System.Windows.Controls.TextBlock
    $sqlUserLbl.Text = "SQL Username:" 
    $sqlUserLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $sqlUserLbl.Margin = "0,0,0,4"
    $stack.Children.Add($sqlUserLbl)

    $sqlUserTxt = New-Object System.Windows.Controls.TextBox
    $sqlUserTxt.Text = $DefaultSqlUser
    $sqlUserTxt.Margin = "0,0,0,12"
    $sqlUserTxt.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $sqlUserTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $sqlUserTxt.Padding = "6,4"
    $sqlUserTxt.IsEnabled = $false
    $stack.Children.Add($sqlUserTxt)

    $pwdLbl = New-Object System.Windows.Controls.TextBlock
    $pwdLbl.Text = "SQL Password:" 
    $pwdLbl.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $pwdLbl.Margin = "0,0,0,4"
    $stack.Children.Add($pwdLbl)

    $pwdBox = New-Object System.Windows.Controls.PasswordBox
    $pwdBox.Margin = "0,0,0,16"
    $pwdBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $pwdBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $pwdBox.Padding = "6,4"
    $pwdBox.IsEnabled = $false
    $stack.Children.Add($pwdBox)

    $authCheck.Add_Checked({
        $sqlUserTxt.IsEnabled = $true
        $pwdBox.IsEnabled = $true
    }.GetNewClosure())
    $authCheck.Add_Unchecked({
        $sqlUserTxt.IsEnabled = $false
        $pwdBox.IsEnabled = $false
    }.GetNewClosure())

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

    $grantBtn = New-Object System.Windows.Controls.Button
    $grantBtn.Content = "Grant"
    $grantBtn.Padding = "14,6"
    $grantBtn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#58A6FF")
    $grantBtn.Foreground = "White"
    $grantBtn.BorderThickness = 0
    $grantBtn.Margin = "0,0,8,0"
    $grantBtn.Add_Click({
        if ([string]::IsNullOrWhiteSpace($loginTxt.Text)) {
            [System.Windows.MessageBox]::Show("Login is required.", "Grant Sysadmin", "OK", "Warning") | Out-Null
            return
        }
        if ($authCheck.IsChecked -eq $true) {
            if ([string]::IsNullOrWhiteSpace($sqlUserTxt.Text)) {
                [System.Windows.MessageBox]::Show("SQL username is required.", "Grant Sysadmin", "OK", "Warning") | Out-Null
                return
            }
            if ([string]::IsNullOrWhiteSpace($pwdBox.Password)) {
                [System.Windows.MessageBox]::Show("SQL password is required.", "Grant Sysadmin", "OK", "Warning") | Out-Null
                return
            }
        }
        $result.Login = $loginTxt.Text.Trim()
        $result.UseSqlAuth = ($authCheck.IsChecked -eq $true)
        $result.SqlUser = $sqlUserTxt.Text.Trim()
        $result.SqlPassword = $pwdBox.Password
        $result.Cancelled = $false
        $dlg.Close()
    }.GetNewClosure())
    $btnPanel.Children.Add($grantBtn)

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
#endregion

#region Show-RestoreDialog
function Show-RestoreDialog {
    param(
        [System.Windows.Window]$OwnerWindow
    )

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
    $dlg.Width = 480
    $dlg.Height = 340
    $dlg.WindowStartupLocation = "CenterOwner"
    if ($OwnerWindow) { $dlg.Owner = $OwnerWindow }
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
#endregion

#region Show-MaintenanceDialog
function Show-MaintenanceDialog {
    param(
        [System.Windows.Window]$OwnerWindow
    )

    $result = @{ Cancelled = $true; Profile = ""; ExportPath = ""; DifferentialPath = ""; ExportDays = 30 }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Online Sync"
    $dlg.Width = 520
    $dlg.Height = 580
    $dlg.WindowStartupLocation = "CenterOwner"
    if ($OwnerWindow) { $dlg.Owner = $OwnerWindow }
    $dlg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#0D1117")
    $dlg.ResizeMode = "NoResize"
    $dlg.Add_KeyDown({ param($s,$e) if ($e.Key -eq [System.Windows.Input.Key]::Escape) { $s.Close() } })

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = "20"

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = "Select Sync Profile"
    $title.FontSize = 14
    $title.FontWeight = "Bold"
    $title.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $title.Margin = "0,0,0,16"
    $stack.Children.Add($title)

    # Radio buttons for sync options
    $radioFull = New-Object System.Windows.Controls.RadioButton
    $radioFull.Content = "Full Sync"
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
    $radioQuick.Content = "Quick Sync"
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
    $syncDesc.Text = "Synchronize and approve updates only (no export)"
    $syncDesc.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $syncDesc.FontSize = 11
    $syncDesc.Margin = "20,0,0,12"
    $stack.Children.Add($syncDesc)

    # Export Settings Section
    $exportTitle = New-Object System.Windows.Controls.TextBlock
    $exportTitle.Text = "Export Settings (optional)"
    $exportTitle.FontSize = 12
    $exportTitle.FontWeight = "SemiBold"
    $exportTitle.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $exportTitle.Margin = "0,0,0,12"
    $stack.Children.Add($exportTitle)

    # Full Export Path
    $exportLabel = New-Object System.Windows.Controls.TextBlock
    $exportLabel.Text = "Full Export Path (backup + all content):"
    $exportLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $exportLabel.FontSize = 11
    $exportLabel.Margin = "0,0,0,4"
    $stack.Children.Add($exportLabel)

    $exportPanel = New-Object System.Windows.Controls.DockPanel
    $exportPanel.Margin = "0,0,0,12"

    $exportBrowse = New-Object System.Windows.Controls.Button
    $exportBrowse.Content = "..."
    $exportBrowse.Width = 30
    $exportBrowse.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $exportBrowse.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $exportBrowse.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($exportBrowse, "Right")
    $exportPanel.Children.Add($exportBrowse)

    $exportBox = New-Object System.Windows.Controls.TextBox
    $exportBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $exportBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $exportBox.BorderThickness = 0
    $exportBox.Padding = "8,6"
    $exportBox.Margin = "0,0,4,0"
    $exportPanel.Children.Add($exportBox)

    $stack.Children.Add($exportPanel)

    # Differential Export Path
    $diffLabel = New-Object System.Windows.Controls.TextBlock
    $diffLabel.Text = "Differential Export Path (recent changes only):"
    $diffLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $diffLabel.FontSize = 11
    $diffLabel.Margin = "0,0,0,4"
    $stack.Children.Add($diffLabel)

    $diffPanel = New-Object System.Windows.Controls.DockPanel
    $diffPanel.Margin = "0,0,0,12"

    $diffBrowse = New-Object System.Windows.Controls.Button
    $diffBrowse.Content = "..."
    $diffBrowse.Width = 30
    $diffBrowse.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $diffBrowse.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $diffBrowse.BorderThickness = 0
    [System.Windows.Controls.DockPanel]::SetDock($diffBrowse, "Right")
    $diffPanel.Children.Add($diffBrowse)

    $diffBox = New-Object System.Windows.Controls.TextBox
    $diffBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $diffBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
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
    $daysLabel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $daysLabel.FontSize = 11
    $daysLabel.VerticalAlignment = "Center"
    $daysPanel.Children.Add($daysLabel)

    $daysBox = New-Object System.Windows.Controls.TextBox
    $daysBox.Text = "30"
    $daysBox.Width = 50
    $daysBox.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#21262D")
    $daysBox.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#E6EDF3")
    $daysBox.BorderThickness = 0
    $daysBox.Padding = "8,4"
    $daysBox.Margin = "8,0,8,0"
    $daysBox.HorizontalContentAlignment = "Center"
    $daysPanel.Children.Add($daysBox)

    $daysLabel2 = New-Object System.Windows.Controls.TextBlock
    $daysLabel2.Text = "days"
    $daysLabel2.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom("#8B949E")
    $daysLabel2.FontSize = 11
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
    $runBtn.Content = "Run Sync"
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
        $result.ExportPath = $exportBox.Text.Trim()
        $result.DifferentialPath = $diffBox.Text.Trim()
        $days = 30
        if ([int]::TryParse($daysBox.Text, [ref]$days)) { $result.ExportDays = $days }
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
#endregion

#region Show-ScheduleTaskDialog
function Show-ScheduleTaskDialog {
    <#
    .SYNOPSIS
        Displays the Schedule Task dialog for configuring monthly maintenance automation.

    .DESCRIPTION
        Creates a WPF modal dialog using XAML for reliable dark theme styling.
        Configures: Schedule type, day, time, maintenance profile, and credentials.

    .PARAMETER OwnerWindow
        The parent WPF window for modal dialog positioning.

    .OUTPUTS
        Hashtable with: Cancelled, Schedule, DayOfWeek, DayOfMonth, Time, Profile, RunAsUser, Password
    #>
    param(
        [System.Windows.Window]$OwnerWindow
    )

    # Result object - local variable (not $script: scope)
    $result = @{
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
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Schedule Online Sync" Width="480" Height="560"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#0D1117">
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
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
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
            <Setter Property="Padding" Value="8,6"/>
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
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="#E6EDF3"/>
        </Style>

        <!-- Dark PasswordBox Style -->
        <Style x:Key="DarkPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="#21262D"/>
            <Setter Property="Foreground" Value="#E6EDF3"/>
            <Setter Property="BorderBrush" Value="#30363D"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="#E6EDF3"/>
        </Style>
    </Window.Resources>

    <StackPanel Margin="20">
        <!-- Title -->
        <TextBlock Text="Create Scheduled Task" FontSize="14" FontWeight="Bold"
                   Foreground="#E6EDF3" Margin="0,0,0,8"/>
        <TextBlock Text="Recommended: Weekly on Saturday at 02:00" FontSize="11"
                   Foreground="#8B949E" Margin="0,0,0,16"/>

        <!-- Schedule Type -->
        <TextBlock Text="Schedule:" Foreground="#8B949E" Margin="0,0,0,4"/>
        <ComboBox x:Name="ScheduleCombo" Style="{StaticResource DarkComboBox}" Margin="0,0,0,12">
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
        <TextBox x:Name="TimeBox" Text="02:00" Style="{StaticResource DarkTextBox}" Margin="0,0,0,12"/>

        <!-- Maintenance Profile -->
        <TextBlock Text="Maintenance Profile:" Foreground="#8B949E" Margin="0,0,0,4"/>
        <ComboBox x:Name="ProfileCombo" Style="{StaticResource DarkComboBox}" Margin="0,0,0,12">
            <ComboBoxItem Content="Full" IsSelected="True"/>
            <ComboBoxItem Content="Quick"/>
            <ComboBoxItem Content="SyncOnly"/>
        </ComboBox>

        <!-- Credentials Section -->
        <TextBlock Text="Run As Credentials (for unattended execution):" Foreground="#8B949E"
                   FontSize="11" Margin="0,4,0,8"/>

        <TextBlock Text="Username (e.g., DoD_Admin or DOMAIN\user):" Foreground="#8B949E" Margin="0,0,0,4"/>
        <TextBox x:Name="UserBox" Text="DoD_Admin" Style="{StaticResource DarkTextBox}" Margin="0,0,0,12"/>

        <TextBlock Text="Password:" Foreground="#8B949E" Margin="0,0,0,4"/>
        <PasswordBox x:Name="PassBox" Style="{StaticResource DarkPasswordBox}" Margin="0,0,0,16"/>

        <!-- Buttons -->
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCreate" Content="Create Task" Padding="14,6"
                    Background="#58A6FF" Foreground="White" BorderThickness="0" Margin="0,0,8,0"/>
            <Button x:Name="BtnCancel" Content="Cancel" Padding="14,6"
                    Background="#21262D" Foreground="#E6EDF3" BorderThickness="0"/>
        </StackPanel>
    </StackPanel>
</Window>
"@

    # Parse XAML and create window
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $dlg = [System.Windows.Markup.XamlReader]::Load($reader)

    # Set owner if available
    if ($null -ne $OwnerWindow) {
        $dlg.Owner = $OwnerWindow
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
            [System.Windows.MessageBox]::Show("Invalid time format. Use HH:mm (e.g., 02:00).", "Schedule", "OK", "Warning") | Out-Null
            return
        }

        # Get schedule type
        $schedVal = $scheduleCombo.SelectedItem.Content

        # Validate day of month if Monthly
        $domVal = 1
        if ($schedVal -eq "Monthly") {
            if (-not [int]::TryParse($domBox.Text, [ref]$domVal) -or $domVal -lt 1 -or $domVal -gt 31) {
                [System.Windows.MessageBox]::Show("Day of month must be between 1 and 31.", "Schedule", "OK", "Warning") | Out-Null
                return
            }
        }

        # Validate credentials
        $userVal = $userBox.Text.Trim()
        $passVal = $passBox.Password
        if ([string]::IsNullOrWhiteSpace($userVal)) {
            [System.Windows.MessageBox]::Show("Username is required for scheduled task execution.", "Schedule", "OK", "Warning") | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($passVal)) {
            [System.Windows.MessageBox]::Show("Password is required for scheduled task execution.`n`nThe task needs credentials to run whether the user is logged on or not.", "Schedule", "OK", "Warning") | Out-Null
            return
        }

        # Store results in local $result (not $script: scope)
        $result.Schedule = $schedVal
        $result.DayOfWeek = $dowCombo.SelectedItem.Content
        $result.DayOfMonth = $domVal
        $result.Time = $timeVal
        $result.Profile = $profileCombo.SelectedItem.Content
        $result.RunAsUser = $userVal
        $result.Password = $passVal
        $result.Cancelled = $false
        $dlg.Close()
    })

    # Cancel button click
    $btnCancel.Add_Click({ $dlg.Close() })

    # Show dialog
    $dlg.ShowDialog() | Out-Null

    # Return result
    return $result
}
#endregion

#region Show-TransferDialog
function Show-TransferDialog {
    param(
        [System.Windows.Window]$OwnerWindow,
        [string]$ServerMode = "Online"
    )

    $result = @{ Cancelled = $true; Direction = ""; Path = ""; SourcePath = ""; DestinationPath = "C:\WSUS"; ExportMode = "Full"; DaysOld = 30 }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Transfer Data"
    $dlg.Width = 480
    $dlg.Height = 460
    $dlg.WindowStartupLocation = "CenterOwner"
    if ($OwnerWindow) { $dlg.Owner = $OwnerWindow }
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
        try { if ($fbd.ShowDialog() -eq "OK") { $pathTxt.Text = $fbd.SelectedPath } }
        finally { $fbd.Dispose() }
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
        try { if ($fbd.ShowDialog() -eq "OK") { $importDestTxt.Text = $fbd.SelectedPath } }
        finally { $fbd.Dispose() }
    }.GetNewClosure())
    $importDestPanel.Children.Add($importDestDock)
    $stack.Children.Add($importDestPanel)

    # Show/hide panels based on direction (must be AFTER $importDestPanel and $pathLbl are created)
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

    # Auto-select mode based on detected server mode (passed as parameter)
    if ($ServerMode -eq "Air-Gap") {
        $radioExport.IsEnabled = $false
        $radioImport.IsChecked = $true
        $exportModePanel.Visibility = "Collapsed"
        $importDestPanel.Visibility = "Visible"
        $pathLbl.Text = "Source folder (external media):"
    }

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
#endregion

#region Show-SettingsDialog
function Show-SettingsDialog {
    param(
        [System.Windows.Window]$OwnerWindow,
        [string]$ContentPath = "C:\WSUS",
        [string]$SqlInstance = ".\SQLEXPRESS"
    )

    $result = @{ Cancelled = $true; ContentPath = $ContentPath; SqlInstance = $SqlInstance }

    $dlg = New-Object System.Windows.Window
    $dlg.Title = "Settings"
    $dlg.Width = 480
    $dlg.Height = 280
    $dlg.WindowStartupLocation = "CenterOwner"
    if ($OwnerWindow) { $dlg.Owner = $OwnerWindow }
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
    $txt1.Text = $ContentPath
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
    $txt2.Text = $SqlInstance
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
        $result.ContentPath = if($txt1.Text){$txt1.Text}else{"C:\WSUS"}
        $result.SqlInstance = if($txt2.Text){$txt2.Text}else{".\SQLEXPRESS"}
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
#endregion

Export-ModuleMember -Function Show-GrantSysadminDialog, Show-RestoreDialog, Show-MaintenanceDialog, Show-ScheduleTaskDialog, Show-TransferDialog, Show-SettingsDialog

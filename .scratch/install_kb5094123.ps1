$secure = ConvertTo-SecureString 'Server123!' -AsPlainText -Force
$cred   = New-Object System.Management.Automation.PSCredential('CM\Install', $secure)
$s = New-PSSession -VMName 'cm-ms02' -Credential $cred

# Stop WsusService so the KB doesn't get blocked on WSUS-related files
Write-Host '=== Stopping WSUS service ==='
Invoke-Command -Session $s -ScriptBlock {
    Stop-Service -Name WsusService -Force -ErrorAction SilentlyContinue
    Stop-Service -Name W3SVC -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Get-Service -Name WsusService,W3SVC -ErrorAction SilentlyContinue |
        Format-Table Name,Status -AutoSize | Out-String | Write-Host
}

# Install KB5094123 via Windows Update COM API
Write-Host '=== Installing KB5094123 (2026-06 Cumulative Update for Server 2019) via Windows Update COM ==='
$installResult = Invoke-Command -Session $s -ScriptBlock {
    # Create an update session
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    Write-Host "Searching for KB5094123..."
    $hit = $searcher.Search("KBArticleIDs='5094123'")
    Write-Host "  Matches: $($hit.Updates.Count)"
    if ($hit.Updates.Count -eq 0) {
        return @{ Ok = $false; Reason = 'KB not found in Windows Update' }
    }
    $kb = $hit.Updates | Select-Object -First 1
    Write-Host "  Title: $($kb.Title)"
    Write-Host "  Size:  $([math]::Round($kb.MaxDownloadSize / 1MB, 1)) MB"

    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $kb

    Write-Host 'Downloading...'
    try {
        $downloadResult = $downloader.Download()
        Write-Host "  Download result: $($downloadResult.ResultCode) (0=NotStarted 1=InProgress 2=Succeeded 3=SucceededWithErrors 4=Failed 5=Aborted)"
        if ($downloadResult.ResultCode -ne 2 -and $downloadResult.ResultCode -ne 3) {
            return @{ Ok = $false; Reason = "Download failed code=$($downloadResult.ResultCode)" }
        }
    } catch {
        return @{ Ok = $false; Reason = "Download threw: $($_.Exception.Message)" }
    }

    $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
    $updatesToInstall.Add($kb) | Out-Null

    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    $installer.AcceptEula = $true

    Write-Host 'Installing (this may take 20-60 min)...'
    $installStart = Get-Date
    try {
        $installResult = $installer.Install()
        $installElapsed = (Get-Date) - $installStart
        Write-Host "  Install result: $($installResult.ResultCode) (0=NotStarted 1=InProgress 2=Succeeded 3=SucceededWithErrors 4=Failed 5=Aborted)"
        Write-Host "  Reboot required: $($installResult.RebootRequired)"
        return @{
            Ok              = ($installResult.ResultCode -eq 2 -or $installResult.ResultCode -eq 3)
            ResultCode      = $installResult.ResultCode
            RebootRequired  = [bool]$installResult.RebootRequired
            ElapsedSeconds  = [int]$installElapsed.TotalSeconds
            Reason          = if ($installResult.ResultCode -eq 2) { 'installed' }
                              elseif ($installResult.ResultCode -eq 3) { 'installed with errors' }
                              else { "code=$($installResult.ResultCode)" }
        }
    } catch {
        return @{ Ok = $false; Reason = "Install threw: $($_.Exception.Message)" }
    }
}

Write-Host ''
Write-Host '=== Install result ==='
$installResult | Format-Table -AutoSize | Out-String | Write-Host

if ($installResult.RebootRequired) {
    Write-Host '=== Rebooting cm-ms02 ==='
    # Graceful shutdown via shutdown.exe, wait for it to come back up
    Invoke-Command -Session $s -ScriptBlock {
        shutdown /r /t 30 /c 'Installing KB5094123' /f 2>&1 | Out-String | Write-Host
    }
    Write-Host 'Reboot initiated; waiting for VM to come back...'
    Remove-PSSession $s -ErrorAction SilentlyContinue

    # Wait for Hyper-V VM to finish rebooting (up to 10 min)
    $vm = Get-VM -Name 'cm-ms02'
    $deadline = (Get-Date).AddMinutes(15)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 30
        try {
            $vm = Get-VM -Name 'cm-ms02'
            $heartbeat = $vm.Heartbeat
            $state = $vm.State
            $uptime = $vm.Uptime.TotalSeconds
            Write-Host "  $(Get-Date -Format 'HH:mm:ss') state=$state uptime=$([int]$uptime)s heartbeat=$heartbeat"
            if ($state -eq 'Running' -and $uptime -lt 600) {
                Write-Host 'VM is up after reboot'
                break
            }
            if ($state -eq 'Off' -and ((Get-Date) - $deadline).TotalSeconds -gt -300) {
                # still off, force on
                Start-VM -Name 'cm-ms02'
            }
        } catch {
            Write-Host "  probe error: $_"
        }
    }
}

Write-Host '=== Verifying KB5094123 is installed post-reboot ==='
$s = New-PSSession -VMName 'cm-ms02' -Credential $cred -ErrorAction Stop
$postKbs = Invoke-Command -Session $s -ScriptBlock {
    Get-HotFix | Where-Object { $_.HotFixID -match '5094123|5034129|5042881|5050041' } |
        Select-Object HotFixID,InstalledOn,InstalledBy |
        Format-Table -AutoSize | Out-String | Write-Host
    # Confirm WSUS service back up
    Get-Service -Name WsusService,W3SVC,SQLBrowser -ErrorAction SilentlyContinue |
        Format-Table Name,Status -AutoSize | Out-String | Write-Host
    # Confirm SQL Server reachable
    try {
        $probe = & sqlcmd -S '.\SQLEXPRESS' -d SUSDB -Q 'SELECT COUNT(*) AS tbUpdate_count FROM tbUpdate' -h -1 2>&1
        Write-Host "tbUpdate count: $($probe[1].Trim())"
    } catch {
        Write-Host "SQL probe failed: $_"
    }
}
Remove-PSSession $s
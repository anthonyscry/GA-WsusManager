$secure = ConvertTo-SecureString 'Server123!' -AsPlainText -Force
$cred   = New-Object System.Management.Automation.PSCredential('CM\Install', $secure)
$s = New-PSSession -VMName 'cm-ms02' -Credential $cred

Write-Host '=== Stop WSUS service before KB install ==='
Invoke-Command -Session $s -ScriptBlock {
    Stop-Service -Name WsusService -Force -ErrorAction SilentlyContinue
    Stop-Service -Name W3SVC -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Get-Service -Name WsusService,W3SVC | Format-Table Name,Status -AutoSize | Out-String | Write-Host
}

Write-Host '=== Installing KB5094123 from pending list ==='
$installResult = Invoke-Command -Session $s -ScriptBlock {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $pending = $searcher.Search('IsInstalled=0').Updates

    # Find the 2026-06 LCU by KBArticleIDs
    $target = $pending | Where-Object {
        $_.KBArticleIDs -contains 5094123 -or
        $_.Title -match '2026-06 Cumulative Update'
    } | Select-Object -First 1

    if (-not $target) {
        return @{ Ok = $false; Reason = 'KB5094123 not in pending list' }
    }

    Write-Host "Target: $($target.Title)"
    Write-Host "  KB IDs:    $($target.KBArticleIDs -join ',')"
    Write-Host "  Size:     $([math]::Round($target.MaxDownloadSize / 1MB, 1)) MB"
    Write-Host "  Mandatory: $($target.IsMandatory)"

    # Build collection of this single update (downloader/installer want a collection)
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    $coll.Add($target) | Out-Null

    # Download
    Write-Host 'Downloading...'
    $dl = $session.CreateUpdateDownloader()
    $dl.Updates = $coll
    try {
        $dlResult = $dl.Download()
        Write-Host "  Download ResultCode: $($dlResult.ResultCode) (2=Succeeded)"
        if ($dlResult.ResultCode -ne 2) {
            return @{ Ok = $false; Reason = "Download code $($dlResult.ResultCode)" }
        }
    } catch {
        return @{ Ok = $false; Reason = "Download threw: $($_.Exception.Message)" }
    }

    # Install
    Write-Host 'Installing (this can take 20-60 min)...'
    $start = Get-Date
    $inst = $session.CreateUpdateInstaller()
    $inst.Updates = $coll
    $inst.AcceptEula = $true
    try {
        $ir = $inst.Install()
        $elapsed = (Get-Date) - $start
        Write-Host "  Install ResultCode: $($ir.ResultCode) (2=Succeeded)"
        Write-Host "  Reboot required:  $($ir.RebootRequired)"
        return @{
            Ok              = ($ir.ResultCode -eq 2 -or $ir.ResultCode -eq 3)
            ResultCode      = $ir.ResultCode
            RebootRequired  = [bool]$ir.RebootRequired
            ElapsedSeconds  = [int]$elapsed.TotalSeconds
        }
    } catch {
        return @{ Ok = $false; Reason = "Install threw: $($_.Exception.Message)" }
    }
}

Write-Host ''
Write-Host '=== Install result ==='
$installResult | Format-Table -AutoSize | Out-String | Write-Host

if ($installResult.Ok -and $installResult.RebootRequired) {
    Write-Host '=== Rebooting cm-ms02 (in 30s)... ==='
    Invoke-Command -Session $s -ScriptBlock {
        shutdown /r /t 30 /c 'Installing KB5094123' /f 2>&1 | Out-String | Write-Host
    }
    Remove-PSSession $s -ErrorAction SilentlyContinue

    Write-Host 'Waiting for VM to come back (up to 10 min)...'
    $deadline = (Get-Date).AddMinutes(15)
    $bootSeen = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 20
        try {
            $vm = Get-VM -Name 'cm-ms02'
            $state = $vm.State
            $uptime = $vm.Uptime.TotalSeconds
            $now = Get-Date -Format 'HH:mm:ss'
            Write-Host "  $now state=$state uptime=$([int]$uptime)s"
            if ($state -eq 'Off' -and -not $bootSeen -and ((Get-Date) - $deadline).TotalSeconds -lt -120) {
                Write-Host 'VM is Off; trying Start-VM'
                Start-VM -Name 'cm-ms02' | Out-Null
                $bootSeen = $true
            }
            if ($state -eq 'Running' -and $uptime -lt 600) {
                Write-Host 'VM is back up after reboot'
                break
            }
        } catch {
            Write-Host "  probe error: $_"
        }
    }

    Write-Host ''
    Write-Host '=== Verifying post-reboot ==='
    $s = New-PSSession -VMName 'cm-ms02' -Credential $cred -ErrorAction Stop
    Invoke-Command -Session $s -ScriptBlock {
        Write-Host '=== Installed KBs containing 5094123 ==='
        Get-HotFix | Where-Object { $_.HotFixID -match '5094123' } |
            Format-Table HotFixID,InstalledOn -AutoSize | Out-String | Write-Host
        Write-Host '=== Services ==='
        Get-Service -Name WsusService,W3SVC,SQLBrowser,'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue |
            Format-Table Name,Status -AutoSize | Out-String | Write-Host
        Write-Host '=== SUSDB probe ==='
        $probe = sqlcmd -S '.\SQLEXPRESS' -d SUSDB -Q 'SELECT COUNT(*) AS cnt FROM tbUpdate' -h -1 -W 2>&1
        $probe | ForEach-Object { Write-Host "  $_" }
    }
    Remove-PSSession $s
}
$secure = ConvertTo-SecureString 'Server123!' -AsPlainText -Force
$cred   = New-Object System.Management.Automation.PSCredential('CM\Install', $secure)
$s = New-PSSession -VMName 'cm-ms02' -Credential $cred

Write-Host '=== Full pending update list ==='
Invoke-Command -Session $s -ScriptBlock {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $pending = $searcher.Search('IsInstalled=0').Updates
    Write-Host "Pending count: $($pending.Count)"
    $pending | Select-Object Title,@{N='KBs';E={$_.KBArticleIDs -join ','}},@{N='Size_MB';E={[math]::Round($_.MaxDownloadSize/1MB,1)}},IsMandatory,IsDownloaded | Format-Table -AutoSize -Wrap | Out-String | Write-Host

    # Try the correct search criteria
    Write-Host '=== Search by KBArticleID (singular) ==='
    $hit = $searcher.Search("KBArticleID='5094123'")
    Write-Host "Matches: $($hit.Updates.Count)"
    if ($hit.Updates.Count -gt 0) {
        $kb = $hit.Updates | Select-Object -First 1
        Write-Host "Title: $($kb.Title)"
    }
}
Remove-PSSession $s
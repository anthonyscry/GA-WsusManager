#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusHistory.psm1

.DESCRIPTION
    Unit tests for the WsusHistory module functions including:
    - Write-WsusOperationHistory (create, trim, retry)
    - Get-WsusOperationHistory (filtering, corrupt-file recovery)
    - Clear-WsusOperationHistory
#>

BeforeAll {
    # Redirect APPDATA to a temp directory so tests never touch real user data
    $script:OriginalAppData = $env:APPDATA
    $tempRoot = [System.IO.Path]::GetTempPath()
    $script:TempAppData = Join-Path $tempRoot "WsusHistoryTests_$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempAppData -Force | Out-Null
    $env:APPDATA = $script:TempAppData

    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusHistory.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking

    # Helper: resolve the history file path under the redirected APPDATA
    function script:Get-TestHistoryPath {
        return Join-Path $env:APPDATA "WsusManager\history.json"
    }

    # Helper: remove the history file to start each test clean
    function script:Reset-TestHistory {
        $p = script:Get-TestHistoryPath
        if (Test-Path $p) { Remove-Item $p -Force }
    }
}

AfterAll {
    Remove-Module WsusHistory -ErrorAction SilentlyContinue
    $env:APPDATA = $script:OriginalAppData
    if (Test-Path $script:TempAppData) {
        Remove-Item $script:TempAppData -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "WsusHistory Module" {
    Context "Module Loading" {
        It "Should import the module successfully" {
            Get-Module WsusHistory | Should -Not -BeNullOrEmpty
        }

        It "Should export Write-WsusOperationHistory" {
            Get-Command Write-WsusOperationHistory -Module WsusHistory | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-WsusOperationHistory" {
            Get-Command Get-WsusOperationHistory -Module WsusHistory | Should -Not -BeNullOrEmpty
        }

        It "Should export Clear-WsusOperationHistory" {
            Get-Command Clear-WsusOperationHistory -Module WsusHistory | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Write-WsusOperationHistory" {
    BeforeEach { script:Reset-TestHistory }
    AfterAll   { script:Reset-TestHistory }

    It "Should create the history file when it does not exist" {
        $histPath = script:Get-TestHistoryPath
        Test-Path $histPath | Should -Be $false

        Write-WsusOperationHistory `
            -OperationType "Cleanup" `
            -Duration (New-TimeSpan -Seconds 15) `
            -Result "Pass"

        Test-Path $histPath | Should -Be $true
    }

    It "Should create the WsusManager directory if missing" {
        $dir = Join-Path $env:APPDATA "WsusManager"
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }

        Write-WsusOperationHistory `
            -OperationType "Install" `
            -Duration (New-TimeSpan -Seconds 5) `
            -Result "Pass"

        Test-Path $dir | Should -Be $true
    }

    It "Should write a valid JSON array" {
        Write-WsusOperationHistory `
            -OperationType "Diagnostics" `
            -Duration (New-TimeSpan -Seconds 30) `
            -Result "Fail" `
            -Summary "Health check found missing service"

        $raw  = Get-Content -Path (script:Get-TestHistoryPath) -Raw
        { $raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "Should store expected fields in the entry" {
        Write-WsusOperationHistory `
            -OperationType "OnlineSync" `
            -Duration (New-TimeSpan -Seconds 120) `
            -Result "Pass" `
            -Summary "Synced 40 updates" `
            -SqlInstance ".\SQLEXPRESS"

        $entries = Get-Content -Path (script:Get-TestHistoryPath) -Raw | ConvertFrom-Json
        $entry   = @($entries)[0]

        $entry.OperationType   | Should -Be "OnlineSync"
        $entry.Result          | Should -Be "Pass"
        $entry.Summary         | Should -Be "Synced 40 updates"
        $entry.DurationSeconds | Should -Be 120.0
        $entry.SqlInstance     | Should -Be ".\SQLEXPRESS"
        $entry.Timestamp       | Should -Not -BeNullOrEmpty
    }

    It "Should prepend new entries (newest first)" {
        Write-WsusOperationHistory -OperationType "Export" -Duration (New-TimeSpan -Seconds 1) -Result "Pass"
        Start-Sleep -Milliseconds 10
        Write-WsusOperationHistory -OperationType "Import" -Duration (New-TimeSpan -Seconds 2) -Result "Fail"

        $entries = @(Get-WsusOperationHistory -Count 10)
        $entries[0].OperationType | Should -Be "Import"
        $entries[1].OperationType | Should -Be "Export"
    }

    It "Should trim history to 100 entries" {
        # Write 105 entries
        for ($i = 1; $i -le 105; $i++) {
            Write-WsusOperationHistory `
                -OperationType "Cleanup" `
                -Duration (New-TimeSpan -Seconds $i) `
                -Result "Pass" `
                -Summary "Entry $i"
        }

        $raw     = Get-Content -Path (script:Get-TestHistoryPath) -Raw | ConvertFrom-Json
        $entries = @($raw)
        $entries.Count | Should -BeLessOrEqual 100
    }

    It "Should keep the newest 100 entries after trimming" {
        for ($i = 1; $i -le 105; $i++) {
            Write-WsusOperationHistory `
                -OperationType "Cleanup" `
                -Duration (New-TimeSpan -Seconds 1) `
                -Result "Pass" `
                -Summary "Entry $i"
        }

        $entries = @(Get-WsusOperationHistory -Count 100)
        # Most recent write had Summary "Entry 105"
        $entries[0].Summary | Should -Be "Entry 105"
        # The 100th entry should be "Entry 6" (105 - 99 = 6)
        $entries[99].Summary | Should -Be "Entry 6"
    }

    It "Should round DurationSeconds to one decimal place" {
        Write-WsusOperationHistory `
            -OperationType "Diagnostics" `
            -Duration (New-TimeSpan -Milliseconds 1234) `
            -Result "Pass"

        $entry = @(Get-WsusOperationHistory -Count 1)[0]
        $entry.DurationSeconds | Should -Be 1.2
    }

    It "Should not throw when called with only mandatory parameters" {
        {
            Write-WsusOperationHistory `
                -OperationType "Cleanup" `
                -Duration (New-TimeSpan -Seconds 0) `
                -Result "Fail"
        } | Should -Not -Throw
    }
}

Describe "Get-WsusOperationHistory" {
    BeforeAll {
        script:Reset-TestHistory
        # Seed known entries
        $types = @("Diagnostics", "Cleanup", "OnlineSync", "Export", "Diagnostics", "Cleanup")
        $results = @("Pass", "Fail", "Pass", "Pass", "Fail", "Pass")
        for ($i = 0; $i -lt $types.Count; $i++) {
            Write-WsusOperationHistory `
                -OperationType $types[$i] `
                -Duration (New-TimeSpan -Seconds ($i + 1)) `
                -Result $results[$i] `
                -Summary "Seed entry $i"
        }
    }

    AfterAll { script:Reset-TestHistory }

    It "Should return entries sorted newest first" {
        $entries = @(Get-WsusOperationHistory -Count 50)
        $entries.Count | Should -BeGreaterThan 0
        # First entry should be the last written ("Cleanup")
        $entries[0].OperationType | Should -Be "Cleanup"
    }

    It "Should respect the Count parameter" {
        $entries = @(Get-WsusOperationHistory -Count 2)
        $entries.Count | Should -Be 2
    }

    It "Should return empty array when no history exists" {
        script:Reset-TestHistory
        $entries = @(Get-WsusOperationHistory)
        $entries.Count | Should -Be 0
    }

    It "Should filter by OperationType" {
        # Re-seed since we wiped in previous test
        Write-WsusOperationHistory -OperationType "Diagnostics" -Duration (New-TimeSpan -Seconds 1) -Result "Pass"
        Write-WsusOperationHistory -OperationType "Cleanup"     -Duration (New-TimeSpan -Seconds 2) -Result "Fail"
        Write-WsusOperationHistory -OperationType "Diagnostics" -Duration (New-TimeSpan -Seconds 3) -Result "Fail"

        $entries = @(Get-WsusOperationHistory -OperationType "Diagnostics")
        $entries | ForEach-Object { $_.OperationType | Should -Be "Diagnostics" }
        $entries.Count | Should -Be 2
    }

    It "Should filter by ResultFilter Pass" {
        script:Reset-TestHistory
        Write-WsusOperationHistory -OperationType "Cleanup" -Duration (New-TimeSpan -Seconds 1) -Result "Pass"
        Write-WsusOperationHistory -OperationType "Cleanup" -Duration (New-TimeSpan -Seconds 2) -Result "Fail"
        Write-WsusOperationHistory -OperationType "Cleanup" -Duration (New-TimeSpan -Seconds 3) -Result "Pass"

        $entries = @(Get-WsusOperationHistory -ResultFilter "Pass")
        $entries.Count | Should -Be 2
        $entries | ForEach-Object { $_.Result | Should -Be "Pass" }
    }

    It "Should filter by ResultFilter Fail" {
        script:Reset-TestHistory
        Write-WsusOperationHistory -OperationType "Export" -Duration (New-TimeSpan -Seconds 1) -Result "Pass"
        Write-WsusOperationHistory -OperationType "Export" -Duration (New-TimeSpan -Seconds 2) -Result "Fail"

        $entries = @(Get-WsusOperationHistory -ResultFilter "Fail")
        $entries.Count | Should -Be 1
        $entries[0].Result | Should -Be "Fail"
    }

    It "Should combine OperationType and ResultFilter" {
        script:Reset-TestHistory
        Write-WsusOperationHistory -OperationType "Diagnostics" -Duration (New-TimeSpan -Seconds 1) -Result "Pass"
        Write-WsusOperationHistory -OperationType "Diagnostics" -Duration (New-TimeSpan -Seconds 2) -Result "Fail"
        Write-WsusOperationHistory -OperationType "Cleanup"     -Duration (New-TimeSpan -Seconds 3) -Result "Fail"

        $entries = @(Get-WsusOperationHistory -OperationType "Diagnostics" -ResultFilter "Fail")
        $entries.Count | Should -Be 1
        $entries[0].OperationType | Should -Be "Diagnostics"
        $entries[0].Result        | Should -Be "Fail"
    }

    It "Should handle corrupt JSON by returning empty array and backing up the file" {
        $histPath = script:Get-TestHistoryPath
        $dir      = Split-Path $histPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $histPath -Value "{ this is not valid json [[[ }" -Encoding UTF8

        $entries = @(Get-WsusOperationHistory)
        $entries.Count | Should -Be 0

        # Backup file should exist
        $backups = Get-ChildItem -Path $dir -Filter "history.json.corrupt.*" -ErrorAction SilentlyContinue
        $backups.Count | Should -BeGreaterThan 0
    }
}

Describe "Clear-WsusOperationHistory" {
    It "Should return true and remove the history file" {
        Write-WsusOperationHistory `
            -OperationType "Install" `
            -Duration (New-TimeSpan -Seconds 60) `
            -Result "Pass"

        $histPath = script:Get-TestHistoryPath
        Test-Path $histPath | Should -Be $true

        $result = Clear-WsusOperationHistory
        $result            | Should -Be $true
        Test-Path $histPath | Should -Be $false
    }

    It "Should return true when history file does not exist" {
        script:Reset-TestHistory
        $result = Clear-WsusOperationHistory
        $result | Should -Be $true
    }
}

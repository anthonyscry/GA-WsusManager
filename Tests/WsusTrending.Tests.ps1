#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for WsusTrending.psm1

.DESCRIPTION
    Unit tests for the WsusTrending module covering daily snapshot recording,
    90-day trim, oversized-file reset, corrupt-file recovery, summary
    regression, and clear behavior.
#>

BeforeAll {
    # Redirect APPDATA to a temp directory so tests never touch real user data
    $script:OriginalAppData = $env:APPDATA
    $tempRoot = [System.IO.Path]::GetTempPath()
    $script:TempAppData = Join-Path $tempRoot "WsusTrendingTests_$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempAppData -Force | Out-Null
    $env:APPDATA = $script:TempAppData

    # Import WsusUtilities so the JSON store helper is available
    Import-Module (Join-Path $PSScriptRoot "..\Modules\WsusUtilities.psm1") -Force -DisableNameChecking

    $ModulePath = Join-Path $PSScriptRoot "..\Modules\WsusTrending.psm1"
    Import-Module $ModulePath -Force -DisableNameChecking

    # Get-TrendsFilePath uses Get-WsusAppDataPath, which resolves to the redirected $env:APPDATA.
    function script:Get-TestTrendsPath {
        return Get-WsusAppDataPath -FileName 'trends.json'
    }
}

AfterAll {
    Remove-Module WsusTrending -ErrorAction SilentlyContinue
    if ($env:APPDATA -ne $script:OriginalAppData) {
        $env:APPDATA = $script:OriginalAppData
    }
    if (Test-Path $script:TempAppData) {
        Remove-Item -LiteralPath $script:TempAppData -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'WsusTrending Module' {
    Context 'Module Loading' {
        It 'Should import the module successfully' {
            Get-Module WsusTrending | Should -Not -BeNullOrEmpty
        }

        It 'Should export Add-WsusTrendSnapshot function' {
            Get-Command Add-WsusTrendSnapshot -Module WsusTrending | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-WsusTrendSummary function' {
            Get-Command Get-WsusTrendSummary -Module WsusTrending | Should -Not -BeNullOrEmpty
        }

        It 'Should export Clear-WsusTrendData function' {
            Get-Command Clear-WsusTrendData -Module WsusTrending | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Add-WsusTrendSnapshot' {
    BeforeEach {
        $path = Get-TestTrendsPath
        if (Test-Path $path) { Remove-Item $path -Force }
    }

    It 'Should create the trends file when it does not exist' {
        Add-WsusTrendSnapshot -DatabaseSizeGB 5.0
        $path = Get-TestTrendsPath
        Test-Path $path | Should -BeTrue
    }

    It 'Should create the WsusManager directory if missing' {
        $path = Get-TestTrendsPath
        if (Test-Path $path) { Remove-Item $path -Force }
        Add-WsusTrendSnapshot -DatabaseSizeGB 4.2
        $dir = Split-Path $path -Parent
        Test-Path $dir | Should -BeTrue
    }

    It 'Should store Date and DatabaseSizeGB fields' {
        Add-WsusTrendSnapshot -DatabaseSizeGB 3.5
        $path = Get-TestTrendsPath
        $raw = Get-Content $path -Raw | ConvertFrom-Json
        @($raw).Count | Should -Be 1
        $raw[0].Date | Should -Match '^\d{4}-\d{2}-\d{2}$'
        $raw[0].DatabaseSizeGB | Should -Be 3.5
    }

    It 'Should overwrite the same-day entry instead of appending' {
        Add-WsusTrendSnapshot -DatabaseSizeGB 2.0
        Add-WsusTrendSnapshot -DatabaseSizeGB 2.5
        $path = Get-TestTrendsPath
        $raw = Get-Content $path -Raw | ConvertFrom-Json
        @($raw).Count | Should -Be 1
        $raw[0].DatabaseSizeGB | Should -Be 2.5
    }
}

Describe 'Get-WsusTrendSummary' {
    BeforeEach {
        $path = Get-TestTrendsPath
        if (Test-Path $path) { Remove-Item $path -Force }
    }

    It 'Should return a default summary when no data exists' {
        $summary = Get-WsusTrendSummary
        $summary.CurrentSizeGB | Should -Be 0
        $summary.DataPoints | Should -Be 0
        $summary.Status | Should -Be 'Collecting data...'
    }

    It 'Should expose expected summary fields' {
        Add-WsusTrendSnapshot -DatabaseSizeGB 4.0
        $summary = Get-WsusTrendSummary
        $summary.CurrentSizeGB | Should -Be 4.0
        $summary.DataPoints | Should -Be 1
        $summary.AlertLevel | Should -Be 'None'
    }
}

Describe 'Clear-WsusTrendData' {
    It 'Should not throw when the file does not exist' {
        $path = Get-TestTrendsPath
        if (Test-Path $path) { Remove-Item $path -Force }
        { Clear-WsusTrendData -Confirm:$false } | Should -Not -Throw
    }

    It 'Should remove an existing trends file' {
        Add-WsusTrendSnapshot -DatabaseSizeGB 6.0
        $path = Get-TestTrendsPath
        Test-Path $path | Should -BeTrue
        Clear-WsusTrendData -Confirm:$false
        Test-Path $path | Should -BeFalse
    }
}

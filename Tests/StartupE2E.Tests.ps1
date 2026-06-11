#Requires -Modules Pester

BeforeDiscovery {
    $script:IsWindowsHost = $env:OS -eq "Windows_NT"
    if ($script:IsWindowsHost) {
        if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
            $script:HostExe = "powershell.exe"
        } elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
            $script:HostExe = "pwsh"
        } else {
            $script:HostExe = $null
        }
    } else {
        $script:HostExe = $null
    }
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:GuiScript = Join-Path $script:RepoRoot "Scripts\WsusManagementGui.ps1"
    $script:HarnessPath = Join-Path $script:RepoRoot "Modules\WsusTestHarness.psm1"
    Import-Module $script:HarnessPath -Force -DisableNameChecking -WarningAction SilentlyContinue
    $script:ProbeTimeoutMs = 90000

    if (-not $script:HostExe -and $script:IsWindowsHost) {
        if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
            $script:HostExe = "powershell.exe"
        } elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
            $script:HostExe = "pwsh"
        }
    }
}

Describe "Startup E2E Probe" -Tag "E2E", "Startup" -Skip:(-not $script:IsWindowsHost) {
    It "Runs startup probe and writes result file" {
        if (-not (Test-Path $script:GuiScript)) { Set-ItResult -Skipped -Because "GUI script not found" }
        $hostExe = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { "powershell.exe" } elseif (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { $null }
        if (-not $hostExe) { Set-ItResult -Skipped -Because "PowerShell host executable not found" }

        $evidenceRoot = New-WsusTestEvidenceRoot -Prefix 'WsusStartupProbe'
        $resultFile = New-WsusTestArtifactPath -RootPath $evidenceRoot -FileName 'startup-probe-result.json'
        $launchArgs = @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", $script:GuiScript
            "-E2EStartupProbe"
            "-E2EStartupProbeSeconds", "8"
            "-E2EResultPath", $resultFile
        )

        $proc = Start-Process -FilePath $hostExe -ArgumentList $launchArgs -PassThru
        $completed = $proc.WaitForExit($script:ProbeTimeoutMs)
        if (-not $completed) {
            $proc.Kill()
            throw "Startup probe timed out after $($script:ProbeTimeoutMs)ms"
        }

        Test-Path $resultFile | Should -BeTrue -Because "Startup probe must emit a JSON result file"

        $raw = Get-Content -Path $resultFile -Raw
        $raw | Should -Not -BeNullOrEmpty
        $result = $raw | ConvertFrom-Json

        $result.status | Should -Not -BeNullOrEmpty
        $result.totalPopupCount | Should -BeGreaterOrEqual 0
        $result.errorPopupCount | Should -BeGreaterOrEqual 0
    }

    It "Reports no startup error popups" {
        if (-not (Test-Path $script:GuiScript)) { Set-ItResult -Skipped -Because "GUI script not found" }
        $hostExe = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { "powershell.exe" } elseif (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { $null }
        if (-not $hostExe) { Set-ItResult -Skipped -Because "PowerShell host executable not found" }

        $evidenceRoot = New-WsusTestEvidenceRoot -Prefix 'WsusStartupProbe'
        $resultFile = New-WsusTestArtifactPath -RootPath $evidenceRoot -FileName 'startup-probe-noerror.json'
        $launchArgs = @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", $script:GuiScript
            "-E2EStartupProbe"
            "-E2EStartupProbeSeconds", "8"
            "-E2EResultPath", $resultFile
        )

        $proc = Start-Process -FilePath $hostExe -ArgumentList $launchArgs -PassThru
        $completed = $proc.WaitForExit($script:ProbeTimeoutMs)
        if (-not $completed) {
            $proc.Kill()
            throw "Startup probe timed out after $($script:ProbeTimeoutMs)ms"
        }

        if (-not (Test-Path $resultFile)) {
            throw "Startup probe did not produce result file: $resultFile"
        }

        $result = (Get-Content -Path $resultFile -Raw) | ConvertFrom-Json

        $detail = "status=$($result.status); reason=$($result.reason); fatal=$($result.fatalError); totalPopups=$($result.totalPopupCount); errorPopups=$($result.errorPopupCount)"
        $result.status | Should -Be "pass" -Because $detail
        $result.errorPopupCount | Should -Be 0 -Because $detail
    }
}

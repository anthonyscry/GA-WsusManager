#Requires -Modules Pester

BeforeDiscovery {
    $script:IsWindowsHost = $env:OS -eq "Windows_NT"
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:GuiScript = Join-Path $script:RepoRoot "Scripts\WsusManagementGui.ps1"
    $script:ProbeTimeoutMs = 90000

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

Describe "Startup E2E Probe" -Tag "E2E", "Startup" -Skip:(-not $script:IsWindowsHost) {
    It "Runs startup probe and writes result file" {
        if (-not (Test-Path $script:GuiScript)) { Set-ItResult -Skipped -Because "GUI script not found" }
        if (-not $script:HostExe) { Set-ItResult -Skipped -Because "PowerShell host executable not found" }

        $resultFile = Join-Path $TestDrive "startup-probe-result.json"
        $launchArgs = @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", $script:GuiScript
            "-E2EStartupProbe"
            "-E2EStartupProbeSeconds", "8"
            "-E2EResultPath", $resultFile
        )

        $proc = Start-Process -FilePath $script:HostExe -ArgumentList $launchArgs -PassThru
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
        if (-not $script:HostExe) { Set-ItResult -Skipped -Because "PowerShell host executable not found" }

        $resultFile = Join-Path $TestDrive "startup-probe-noerror.json"
        $launchArgs = @(
            "-NoProfile"
            "-ExecutionPolicy", "Bypass"
            "-File", $script:GuiScript
            "-E2EStartupProbe"
            "-E2EStartupProbeSeconds", "8"
            "-E2EResultPath", $resultFile
        )

        $proc = Start-Process -FilePath $script:HostExe -ArgumentList $launchArgs -PassThru
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

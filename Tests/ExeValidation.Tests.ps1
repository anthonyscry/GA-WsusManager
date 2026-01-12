#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for validating the compiled WsusManager.exe

.DESCRIPTION
    Tests to verify the compiled executable:
    - File exists and has valid size
    - PE header is valid
    - Version information is embedded
    - Required resources are present
    - Startup benchmark (optional)
#>

# BeforeDiscovery runs before test discovery, allowing -Skip parameters to use these variables
BeforeDiscovery {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ExeName = "WsusManager.exe"
    $script:ExePath = $null

    # Check multiple possible locations for the exe
    $possiblePaths = @(
        (Join-Path $script:RepoRoot $script:ExeName),
        (Join-Path $script:RepoRoot "dist" $script:ExeName),
        (Join-Path $script:RepoRoot "GA-WsusManager.exe"),
        (Join-Path $script:RepoRoot "dist" "GA-WsusManager.exe")
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $script:ExePath = $path
            break
        }
    }

    $script:ExeExists = $null -ne $script:ExePath -and (Test-Path $script:ExePath)
}

BeforeAll {
    # Re-establish variables for test runtime (BeforeDiscovery vars aren't automatically available)
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ExeName = "WsusManager.exe"
    $script:ExePath = $null

    $possiblePaths = @(
        (Join-Path $script:RepoRoot $script:ExeName),
        (Join-Path $script:RepoRoot "dist" $script:ExeName),
        (Join-Path $script:RepoRoot "GA-WsusManager.exe"),
        (Join-Path $script:RepoRoot "dist" "GA-WsusManager.exe")
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $script:ExePath = $path
            break
        }
    }

    $script:ExeExists = $null -ne $script:ExePath -and (Test-Path $script:ExePath)
}

Describe "EXE Validation Tests" {
    Context "File Existence and Basic Properties" -Skip:(-not $script:ExeExists) {
        It "Should have WsusManager.exe in repo root or dist folder" {
            $script:ExePath | Should -Not -BeNullOrEmpty -Because "ExePath should be set"
            (Test-Path $script:ExePath) | Should -Be $true -Because "The compiled executable should exist"
        }

        It "Should have a reasonable file size (> 100KB)" {
            $fileInfo = Get-Item $script:ExePath
            $fileInfo.Length | Should -BeGreaterThan 100KB -Because "PS2EXE output should be at least 100KB"
        }

        It "Should have a reasonable file size (< 50MB)" {
            $fileInfo = Get-Item $script:ExePath
            $fileInfo.Length | Should -BeLessThan 50MB -Because "Executable should not be excessively large"
        }

        It "Should be a recent build (modified within last 30 days)" -Tag "CI" {
            $fileInfo = Get-Item $script:ExePath
            $fileInfo.LastWriteTime | Should -BeGreaterThan (Get-Date).AddDays(-30) -Because "Build should be recent"
        }
    }

    Context "PE Header Validation" -Skip:(-not $script:ExeExists) {
        It "Should have valid PE signature (MZ header)" {
            $bytes = [System.IO.File]::ReadAllBytes($script:ExePath)
            $bytes.Length | Should -BeGreaterThan 64

            # Check MZ signature (0x4D, 0x5A = "MZ")
            $bytes[0] | Should -Be 0x4D -Because "First byte should be 'M'"
            $bytes[1] | Should -Be 0x5A -Because "Second byte should be 'Z'"
        }

        It "Should have PE signature at correct offset" {
            $bytes = [System.IO.File]::ReadAllBytes($script:ExePath)

            # PE offset is at 0x3C (4 bytes, little-endian)
            $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
            $peOffset | Should -BeGreaterThan 0 -Because "PE offset should be positive"

            # Check PE signature (0x50, 0x45, 0x00, 0x00 = "PE\0\0")
            $bytes[$peOffset] | Should -Be 0x50 -Because "PE signature byte 1 should be 'P'"
            $bytes[$peOffset + 1] | Should -Be 0x45 -Because "PE signature byte 2 should be 'E'"
        }

        It "Should be a 64-bit executable" {
            $bytes = [System.IO.File]::ReadAllBytes($script:ExePath)
            $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)

            # Machine type is at PE offset + 4 (2 bytes)
            # 0x8664 = AMD64 (x64)
            # 0x014C = i386 (x86)
            $machineType = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
            $machineType | Should -Be 0x8664 -Because "Build should produce 64-bit executable"
        }
    }

    Context "Version Information" -Skip:(-not $script:ExeExists) {
        It "Should have embedded version information" {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($script:ExePath)
            $versionInfo | Should -Not -BeNullOrEmpty
        }

        It "Should have valid product name" {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($script:ExePath)
            $versionInfo.ProductName | Should -Be "WSUS Manager" -Because "Product name should match build configuration"
        }

        It "Should have valid company name" {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($script:ExePath)
            $versionInfo.CompanyName | Should -Be "GA-ASI" -Because "Company name should match build configuration"
        }

        It "Should have a version number" {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($script:ExePath)
            $versionInfo.FileVersion | Should -Match '^\d+\.\d+\.\d+' -Because "Version should be in semver format"
        }

        It "Should have matching file and product version" {
            $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($script:ExePath)
            $fileVer = $versionInfo.FileVersion -replace '\.0$', ''
            $prodVer = $versionInfo.ProductVersion -replace '\.0$', ''
            $fileVer | Should -Be $prodVer -Because "File and product versions should match"
        }
    }

    Context "Startup Benchmark" -Tag "Benchmark", "CI" -Skip:(-not $script:ExeExists) {
        It "Should start within acceptable time (< 10 seconds)" {
            # We can't actually run the GUI in CI, but we can verify the script parses quickly
            $guiScript = Join-Path $script:RepoRoot "Scripts" "WsusManagementGui.ps1"
            if (-not (Test-Path $guiScript)) { Set-ItResult -Skipped -Because "GUI script not found" }

            $parseStart = Get-Date
            $null = [System.Management.Automation.Language.Parser]::ParseFile($guiScript, [ref]$null, [ref]$null)
            $parseDuration = (Get-Date) - $parseStart

            $parseDuration.TotalSeconds | Should -BeLessThan 5 -Because "Script should parse in under 5 seconds"
        }

        It "Should have no syntax errors in main script" {
            $guiScript = Join-Path $script:RepoRoot "Scripts" "WsusManagementGui.ps1"
            if (-not (Test-Path $guiScript)) { Set-ItResult -Skipped -Because "GUI script not found" }

            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($guiScript, [ref]$null, [ref]$errors)

            $errors.Count | Should -Be 0 -Because "Script should have no syntax errors"
        }
    }

    Context "Distribution Package" -Tag "CI" -Skip:(-not $script:ExeExists) {
        It "Should have distribution zip if exe exists" {
            $zipFiles = Get-ChildItem -Path $script:RepoRoot -Filter "WsusManager-v*.zip" -ErrorAction SilentlyContinue
            $distZip = Get-ChildItem -Path (Join-Path $script:RepoRoot "dist") -Filter "WsusManager-v*.zip" -ErrorAction SilentlyContinue

            ($zipFiles.Count -gt 0 -or $distZip.Count -gt 0) | Should -Be $true -Because "Distribution zip should exist"
        }
    }
}

Describe "AsyncHelpers Module Validation" {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent $PSScriptRoot
        $script:AsyncModulePath = Join-Path $script:RepoRoot "Modules" "AsyncHelpers.psm1"
    }

    Context "Module Loading" {
        It "Should have AsyncHelpers.psm1 module file" {
            Test-Path $script:AsyncModulePath | Should -Be $true
        }

        It "Should import without errors" {
            { Import-Module $script:AsyncModulePath -Force -DisableNameChecking } | Should -Not -Throw
        }

        It "Should export expected functions" {
            Import-Module $script:AsyncModulePath -Force -DisableNameChecking
            $commands = Get-Command -Module AsyncHelpers

            $expectedFunctions = @(
                'Initialize-AsyncRunspacePool',
                'Close-AsyncRunspacePool',
                'Invoke-Async',
                'Wait-Async',
                'Test-AsyncComplete',
                'Stop-Async',
                'Invoke-UIThread',
                'Start-BackgroundOperation'
            )

            foreach ($func in $expectedFunctions) {
                $commands.Name | Should -Contain $func -Because "$func should be exported"
            }
        }
    }

    AfterAll {
        Remove-Module AsyncHelpers -ErrorAction SilentlyContinue
    }
}

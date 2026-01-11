<#
.SYNOPSIS
    Shared test setup script for WSUS Manager Pester tests

.DESCRIPTION
    Pre-loads all WSUS modules once to avoid repeated Import-Module calls
    across test files. Each test file should dot-source this script in
    its BeforeAll block, then only re-import its specific module under test.

.NOTES
    Performance optimization: Loading modules once instead of per-file
    reduces test suite time by 20-30 seconds.
#>

$script:TestSetupLoaded = $true
$script:ModulesPath = Join-Path $PSScriptRoot "..\Modules"

# List of all WSUS modules to pre-load
$script:WsusModules = @(
    "WsusUtilities"
    "WsusServices"
    "WsusFirewall"
    "WsusPermissions"
    "WsusDatabase"
    "WsusHealth"
    "WsusConfig"
    "WsusExport"
    "WsusScheduledTask"
    "WsusAutoDetection"
)

# Pre-load all modules if not already loaded
foreach ($moduleName in $script:WsusModules) {
    $modulePath = Join-Path $script:ModulesPath "$moduleName.psm1"
    if (Test-Path $modulePath) {
        if (-not (Get-Module $moduleName)) {
            Import-Module $modulePath -DisableNameChecking -ErrorAction SilentlyContinue
        }
    }
}

# Helper function to get module path
function Get-WsusTestModulePath {
    param([string]$ModuleName)
    return Join-Path $script:ModulesPath "$ModuleName.psm1"
}

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
    "AsyncHelpers"
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

# Test configuration settings
$script:TestConfig = @{
    # Timeouts (in seconds)
    DefaultTimeout = 30
    ServiceStartTimeout = 5      # Reduced from default - services may not exist on dev machines
    AppStartTimeout = 10
    ElementSearchTimeout = 5

    # Skip conditions
    SkipServiceTests = -not (Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue)
    SkipFlaUITests = -not (Test-Path "C:\projects\FlaUI-TestHarness\FlaUITestHarness.psm1")
    SkipInteractiveTests = $true  # Always skip tests requiring user input

    # Paths
    ProjectRoot = Split-Path -Parent $PSScriptRoot
    ExeName = "GA-WsusManager.exe"
}

# Helper to check if test should be skipped
function Test-ShouldSkipServiceTest {
    return $script:TestConfig.SkipServiceTests
}

function Test-ShouldSkipFlaUITest {
    return $script:TestConfig.SkipFlaUITests
}

function Test-ShouldSkipInteractiveTest {
    return $script:TestConfig.SkipInteractiveTests
}

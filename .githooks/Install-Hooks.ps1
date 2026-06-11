<#
.SYNOPSIS
    Install Git hooks for GA-WsusManager

.DESCRIPTION
    Copies the pre-commit hook to the .git/hooks directory and makes it executable.

.EXAMPLE
    .\.githooks\Install-Hooks.ps1
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$gitHooksDir = Join-Path $repoRoot ".git\hooks"
$sourceHook = Join-Path $PSScriptRoot "pre-commit"
$destHook = Join-Path $gitHooksDir "pre-commit"

Write-Host "Installing Git hooks for GA-WsusManager..." -ForegroundColor Cyan

# Check if we're in a git repo
if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
    Write-Host "[ERROR] Not a Git repository" -ForegroundColor Red
    exit 1
}

# Create hooks directory if needed
if (-not (Test-Path $gitHooksDir)) {
    New-Item -ItemType Directory -Path $gitHooksDir -Force | Out-Null
}

# Copy pre-commit hook
if (Test-Path $sourceHook) {
    Copy-Item -Path $sourceHook -Destination $destHook -Force
    Write-Host "[OK] Installed pre-commit hook" -ForegroundColor Green
} else {
    Write-Host "[ERROR] pre-commit hook not found in .githooks" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Git hooks installed successfully!" -ForegroundColor Green
Write-Host "The pre-commit hook will run PSScriptAnalyzer on staged files." -ForegroundColor Gray

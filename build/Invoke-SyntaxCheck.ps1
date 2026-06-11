<#
.SYNOPSIS
    Quick syntax check for all PowerShell files in the repo.

.DESCRIPTION
    Uses the PowerShell parser to verify all .ps1, .psm1, and .psd1 files
    parse cleanly. Faster than running PSScriptAnalyzer and is the
    appropriate pre-commit gate. Returns non-zero exit code if any file
    has a parse error.

.PARAMETER Path
    Root path to scan. Defaults to repo root.

.EXAMPLE
    .\build\Invoke-SyntaxCheck.ps1
    # Scan everything in the repo

.EXAMPLE
    .\build\Invoke-SyntaxCheck.ps1 -Path Modules
    # Scan only Modules directory
#>

[CmdletBinding()]
param(
    [string]$Path
)

if (-not $Path) {
    $Path = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
}
$root = (Resolve-Path $Path).Path

$files = Get-ChildItem -Path $root -Include '*.ps1', '*.psm1', '*.psd1' -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '[\\/](\.git|node_modules|bin|obj|dist|\.planning-archive-reverted-c#-era)[\\/]'
    }

$errors = 0
$parsed = 0

Write-Host ""
Write-Host "PowerShell Syntax Check" -ForegroundColor Cyan
Write-Host "  Root:  $root" -ForegroundColor Gray
Write-Host "  Files: $($files.Count)" -ForegroundColor Gray
Write-Host ""

foreach ($file in $files) {
    $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/')
    $tokens = $null
    $parseErrors = $null
    try {
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Write-Host "  [FAIL] $relative" -ForegroundColor Red
            foreach ($err in $parseErrors) {
                Write-Host "    Line $($err.Extent.StartLine): $($err.Message)" -ForegroundColor Red
                $errors++
            }
        } else {
            Write-Host "  [OK]   $relative" -ForegroundColor Green
            $parsed++
        }
    } catch {
        Write-Host "  [ERR]  $relative : $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "Summary: $parsed passed, $errors error(s)" -ForegroundColor $(if ($errors -gt 0) { 'Red' } else { 'Green' })

if ($errors -gt 0) {
    exit 1
} else {
    exit 0
}

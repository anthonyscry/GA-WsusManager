#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$PackageRoot = '',
    [string]$FlaUIVersion = '5.0.0'
)
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Join-Path $PSScriptRoot 'packages'
}


$ErrorActionPreference = 'Stop'

function Save-FlaUIPackage {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Destination
    )

    $packageDirectory = Join-Path $Destination $Name
    $existing = Get-ChildItem -Path $packageDirectory -Filter '*.dll' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { return }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    if (Get-Command Save-Package -ErrorAction SilentlyContinue) {
        try {
            Save-Package -Name $Name -RequiredVersion $Version -Source 'https://api.nuget.org/v3/index.json' -Path $Destination -ProviderName NuGet -Force -ErrorAction Stop | Out-Null
            return
        } catch {
            Write-Warning "Save-Package failed for ${Name} ${Version}: $($_.Exception.Message)"
        }
    }

    $nupkgPath = Join-Path $Destination ("{0}.{1}.nupkg" -f $Name, $Version)
    $url = "https://www.nuget.org/api/v2/package/$Name/$Version"
    Invoke-WebRequest -Uri $url -OutFile $nupkgPath -UseBasicParsing
    $extractPath = Join-Path $Destination ("{0}.{1}" -f $Name, $Version)
    if (Test-Path $extractPath) { Remove-Item -Path $extractPath -Recurse -Force }
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($nupkgPath, $extractPath)
}


Save-FlaUIPackage -Name 'Interop.UIAutomationClient' -Version '10.19041.0' -Destination $PackageRoot
Save-FlaUIPackage -Name 'FlaUI.Core' -Version $FlaUIVersion -Destination $PackageRoot
Save-FlaUIPackage -Name 'FlaUI.UIA3' -Version $FlaUIVersion -Destination $PackageRoot

Write-Host "FlaUI packages are available under $PackageRoot"

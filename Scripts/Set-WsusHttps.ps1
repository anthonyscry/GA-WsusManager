#Requires -RunAsAdministrator

<#
===============================================================================
Script: Set-WsusHttps.ps1
Author: Tony Tran, ISSO, GA-ASI
Version: 1.0.1
Date: 2026-01-10
===============================================================================

.SYNOPSIS
    Configure WSUS to use HTTPS (SSL/TLS) instead of HTTP.

.DESCRIPTION
    Enables HTTPS on the WSUS server by:
    - Creating a self-signed certificate OR using an existing certificate
    - Binding the certificate to IIS on port 8531
    - Configuring WSUS for SSL using wsusutil.exe
    - Optionally updating the WSUS GPO with the new HTTPS URL

.PARAMETER CertificateThumbprint
    Thumbprint of an existing certificate to use. If not provided, prompts interactively.

.EXAMPLE
    .\Set-WsusHttps.ps1
    Interactive mode - prompts for certificate choice.

.EXAMPLE
    .\Set-WsusHttps.ps1 -CertificateThumbprint "1234567890ABCDEF..."
    Uses the specified existing certificate.

.NOTES
    Requirements:
    - Run on the WSUS server with Administrator privileges
    - IIS and WSUS must be installed
    - For GPO update: Run Set-WsusGroupPolicy.ps1 on DC after this script
#>

[CmdletBinding()]
param(
    [string]$CertificateThumbprint
)

# Import WsusUtilities for logging
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\WsusUtilities.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -DisableNameChecking -ErrorAction SilentlyContinue
}

#region Helper Functions

function Show-CertificateMenu {
    <#
    .SYNOPSIS
        Displays menu for certificate selection.
    #>
    Write-Host ""
    Write-Host "SSL Certificate Options" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Create self-signed certificate"
    Write-Host "  2. Use existing certificate from Local Machine store"
    Write-Host "  3. Cancel"
    Write-Host ""

    $choice = Read-Host "Select option (1-3)"
    return $choice
}

function New-WsusSelfSignedCert {
    <#
    .SYNOPSIS
        Creates a self-signed certificate for WSUS.
    #>
    param([string]$ServerName)

    Write-Host "Creating self-signed certificate..." -NoNewline

    # Get FQDN
    $fqdn = [System.Net.Dns]::GetHostEntry($ServerName).HostName
    if (-not $fqdn) { $fqdn = $ServerName }

    # Create certificate valid for 5 years
    $cert = New-SelfSignedCertificate `
        -DnsName $fqdn, $ServerName, "localhost" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(5) `
        -FriendlyName "WSUS SSL Certificate" `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") `
        -ErrorAction Stop

    Write-Host " OK" -ForegroundColor Green
    Write-Host "  Subject: $($cert.Subject)"
    Write-Host "  Thumbprint: $($cert.Thumbprint)"
    Write-Host "  Expires: $($cert.NotAfter.ToString('yyyy-MM-dd'))"

    return $cert
}

function Select-ExistingCertificate {
    <#
    .SYNOPSIS
        Lists and prompts for selection of existing certificates.
    #>

    Write-Host ""
    Write-Host "Searching for certificates..." -NoNewline

    # Get certificates with private key that are valid for server auth
    $certs = Get-ChildItem -Path Cert:\LocalMachine\My |
        Where-Object {
            $_.HasPrivateKey -and
            $_.NotAfter -gt (Get-Date) -and
            ($_.EnhancedKeyUsageList.ObjectId -contains "1.3.6.1.5.5.7.3.1" -or $_.EnhancedKeyUsageList.Count -eq 0)
        } |
        Sort-Object NotAfter -Descending

    if ($certs.Count -eq 0) {
        Write-Host " None found" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "No valid certificates found. Requirements:" -ForegroundColor Yellow
        Write-Host "  - Must have private key"
        Write-Host "  - Must not be expired"
        Write-Host "  - Must be valid for Server Authentication"
        return $null
    }

    Write-Host " $($certs.Count) found" -ForegroundColor Green
    Write-Host ""
    Write-Host "Available Certificates:" -ForegroundColor Cyan
    Write-Host ""

    $i = 1
    foreach ($cert in $certs) {
        $subject = $cert.Subject -replace '^CN=', ''
        if ($subject.Length -gt 40) { $subject = $subject.Substring(0, 37) + "..." }
        $expires = $cert.NotAfter.ToString('yyyy-MM-dd')
        $friendly = if ($cert.FriendlyName) { " ($($cert.FriendlyName))" } else { "" }

        Write-Host "  [$i] $subject$friendly"
        Write-Host "      Expires: $expires | Thumbprint: $($cert.Thumbprint.Substring(0,16))..."
        $i++
    }

    Write-Host ""
    Write-Host "  [0] Cancel"
    Write-Host ""

    $selection = Read-Host "Select certificate (0-$($certs.Count))"

    if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
        return $null
    }

    $index = 0
    if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $certs.Count) {
        return $certs[$index - 1]
    }

    Write-Host "Invalid selection" -ForegroundColor Red
    return $null
}

function Set-IISHttpsBinding {
    <#
    .SYNOPSIS
        Binds certificate to IIS WSUS site on port 8531.
    #>
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    Write-Host "Configuring IIS HTTPS binding..." -NoNewline

    Import-Module WebAdministration -ErrorAction Stop

    # Find WSUS Administration site
    $wsussite = Get-Website | Where-Object { $_.Name -like "*WSUS*" } | Select-Object -First 1
    if (-not $wsussite) {
        $wsussite = Get-Website | Where-Object { $_.Id -eq 1 } | Select-Object -First 1  # Default Web Site
    }

    if (-not $wsussite) {
        throw "Could not find WSUS website in IIS"
    }

    $siteName = $wsussite.Name

    # Check if HTTPS binding already exists
    $existingBinding = Get-WebBinding -Name $siteName -Protocol "https" -Port 8531 -ErrorAction SilentlyContinue

    if ($existingBinding) {
        # Remove existing binding
        Remove-WebBinding -Name $siteName -Protocol "https" -Port 8531 -ErrorAction SilentlyContinue
    }

    # Create new HTTPS binding
    New-WebBinding -Name $siteName -Protocol "https" -Port 8531 -IPAddress "*" -ErrorAction Stop

    # Bind certificate to the new binding
    $binding = Get-WebBinding -Name $siteName -Protocol "https" -Port 8531
    $binding.AddSslCertificate($Certificate.Thumbprint, "My")

    Write-Host " OK" -ForegroundColor Green
    Write-Host "  Site: $siteName"
    Write-Host "  Port: 8531 (HTTPS)"

    return $siteName
}

function Set-WsusSSLConfiguration {
    <#
    .SYNOPSIS
        Configures WSUS to require SSL using wsusutil.exe.
    #>

    Write-Host "Configuring WSUS for SSL..." -NoNewline

    $wsusutil = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    if (-not (Test-Path $wsusutil)) {
        throw "wsusutil.exe not found at $wsusutil"
    }

    # Configure SSL - this enables SSL for client communication
    $result = & $wsusutil configuressl (hostname) 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host " Warning" -ForegroundColor Yellow
        Write-Host "  wsusutil output: $result"
    } else {
        Write-Host " OK" -ForegroundColor Green
    }
}

function Add-CertToTrustedRoot {
    <#
    .SYNOPSIS
        Copies self-signed certificate to Trusted Root store for local trust.
    #>
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    Write-Host "Adding certificate to Trusted Root store..." -NoNewline

    # Check if already in trusted root
    $existing = Get-ChildItem -Path Cert:\LocalMachine\Root |
        Where-Object { $_.Thumbprint -eq $Certificate.Thumbprint }

    if ($existing) {
        Write-Host " Already exists" -ForegroundColor DarkGray
        return
    }

    # Export and import to Root store
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")
    $store.Add($Certificate)
    $store.Close()

    Write-Host " OK" -ForegroundColor Green
    Write-Host "  NOTE: For domain clients, deploy this cert via GPO or manually" -ForegroundColor Yellow
}

function Export-CertificateForDistribution {
    <#
    .SYNOPSIS
        Exports certificate (public key only) for distribution to clients.
    #>
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $exportPath = "C:\WSUS\WSUS-SSL-Certificate.cer"

    Write-Host "Exporting certificate for client distribution..." -NoNewline

    # Ensure directory exists
    $dir = Split-Path $exportPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    # Export public key only
    $certBytes = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    [System.IO.File]::WriteAllBytes($exportPath, $certBytes)

    Write-Host " OK" -ForegroundColor Green
    Write-Host "  Exported to: $exportPath"
    Write-Host "  Distribute this file to clients or deploy via GPO" -ForegroundColor Yellow

    return $exportPath
}

function Show-Summary {
    <#
    .SYNOPSIS
        Displays configuration summary.
    #>
    param(
        [string]$ServerName,
        [string]$CertExportPath,
        [bool]$IsSelfSigned
    )

    $httpsUrl = "https://$($ServerName):8531"

    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host " HTTPS Configuration Complete" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "WSUS HTTPS URL: " -NoNewline
    Write-Host $httpsUrl -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Test HTTPS access: Open $httpsUrl in browser"
    Write-Host "  2. Update GPO on Domain Controller:"
    Write-Host "     .\Set-WsusGroupPolicy.ps1 -WsusServerUrl `"$httpsUrl`""

    if ($IsSelfSigned) {
        Write-Host ""
        Write-Host "  3. Deploy certificate to clients (self-signed cert):"
        Write-Host "     - Copy $CertExportPath to clients"
        Write-Host "     - Import to Trusted Root CA store, or"
        Write-Host "     - Deploy via GPO (Computer Config > Policies > Windows Settings >"
        Write-Host "       Security Settings > Public Key Policies > Trusted Root CAs)"
    }

    Write-Host ""
}

#endregion

#region Main Script

# Initialize logging if WsusUtilities is available
$loggingEnabled = $false
if (Get-Command Start-WsusLogging -ErrorAction SilentlyContinue) {
    Start-WsusLogging -LogPath "C:\WSUS\Logs\Set-WsusHttps.log"
    $loggingEnabled = $true
    Write-Log "HTTPS configuration started"
}

try {
    # Display banner
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host " WSUS HTTPS Configuration" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""

    $serverName = hostname
    Write-Host "Server: $serverName"

    # Check if WSUS is installed
    $wsusutil = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    if (-not (Test-Path $wsusutil)) {
        throw "WSUS does not appear to be installed (wsusutil.exe not found)"
    }
    Write-Host "WSUS: Installed"

    # Certificate selection
    $certificate = $null
    $isSelfSigned = $false

    if ($CertificateThumbprint) {
        # Use provided thumbprint
        $certificate = Get-ChildItem -Path Cert:\LocalMachine\My |
            Where-Object { $_.Thumbprint -eq $CertificateThumbprint }

        if (-not $certificate) {
            throw "Certificate with thumbprint $CertificateThumbprint not found"
        }
        Write-Host "Certificate: Using provided thumbprint"
    } else {
        # Interactive menu
        $choice = Show-CertificateMenu

        switch ($choice) {
            "1" {
                # Self-signed
                $certificate = New-WsusSelfSignedCert -ServerName $serverName
                $isSelfSigned = $true
            }
            "2" {
                # Existing
                $certificate = Select-ExistingCertificate
                if (-not $certificate) {
                    Write-Host "No certificate selected. Exiting." -ForegroundColor Yellow
                    exit 0
                }
            }
            "3" {
                Write-Host "Cancelled." -ForegroundColor Yellow
                exit 0
            }
            default {
                Write-Host "Invalid option. Exiting." -ForegroundColor Red
                exit 1
            }
        }
    }

    Write-Host ""
    Write-Host "Configuring HTTPS..." -ForegroundColor Yellow
    Write-Host ""

    # Configure IIS binding
    Set-IISHttpsBinding -Certificate $certificate

    # Configure WSUS SSL
    Set-WsusSSLConfiguration

    # For self-signed certs, add to trusted root and export
    $certExportPath = $null
    if ($isSelfSigned) {
        Add-CertToTrustedRoot -Certificate $certificate
        $certExportPath = Export-CertificateForDistribution -Certificate $certificate
    }

    # Show summary
    Show-Summary -ServerName $serverName -CertExportPath $certExportPath -IsSelfSigned $isSelfSigned

    if ($loggingEnabled) {
        Write-Log "HTTPS configuration completed successfully"
    }

} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    if ($loggingEnabled) {
        Write-Log "ERROR: $($_.Exception.Message)"
    }
    exit 1
} finally {
    if ($loggingEnabled) {
        Stop-WsusLogging
    }
}

#endregion

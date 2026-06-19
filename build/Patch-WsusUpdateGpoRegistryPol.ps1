<#
.SYNOPSIS
Patches the AU settings in the WSUS Update Policy GPO backup's
registry.pol file.

.DESCRIPTION
Reads the existing machine-side registry.pol for the WSUS Update
Policy backup, applies four AU setting changes, and writes the
patched file back in place.

Changes:
  - AUOptions: 2 -> 4 (auto-download + auto-install + prompt to restart)
  - AlwaysAutoRebootAtScheduledTime: 1 -> 0 (no forced reboot at scheduled time)
  - NoAutoRebootWithLoggedOnUsers: add as 1 (skip reboot if a user is signed in)
  - NoAUShutdownOption: 0 -> 1 (block shutdown while updates are in progress)

Day/time/schedule preserved.

.PARAMETER PolPath
Path to the registry.pol file inside the GPO backup.

.EXAMPLE
.\Patch-WsusUpdateGpoRegistryPol.ps1
#>

[CmdletBinding()]
param(
    [string]$PolPath
)

if (-not $PolPath) {
    $defaultPath = Join-Path $PSScriptRoot '..\DomainController\WSUS GPOs\{A806083D-AB0A-4A33-B009-081B64F0A72D}\DomainSysvol\GPO\Machine\registry.pol'
    $PolPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $defaultPath).Path)
}

$ErrorActionPreference = 'Stop'

# === Format reference (MS-PRREG) ===
# Header (8 bytes): PReg + version (DWORD LE) + flags (DWORD LE)
# Each entry is bracketed by 0x5B 0x00 ... 0x5D 0x00:
#   [ NUL  <key_UTF16LE_NULTERM>  ; NUL  <value_UTF16LE_NULTERM>  ; NUL  <type_LE_4>  ; NUL  <size_LE_4>  ; NUL  <data>  ; NUL  ] NUL

$POL_HEADER = New-Object byte[] 8
[byte[]]$POL_HEADER_BYTES = 0x50, 0x52, 0x65, 0x67, 0x01, 0x00, 0x00, 0x00
[Array]::Copy($POL_HEADER_BYTES, $POL_HEADER, 8)

function Read-U32LE([byte[]]$Buf, [int]$Offset) {
    return [BitConverter]::ToUInt32($Buf, $Offset)
}

function Read-NulTermUtf16([byte[]]$Buf, [int]$Offset) {
    $ue = [System.Text.Encoding]::Unicode
    $start = $Offset
    while ($Offset -lt $Buf.Length - 1) {
        if ($Buf[$Offset] -eq 0 -and $Buf[$Offset + 1] -eq 0) { break }
        $Offset += 2
    }
    $str = if ($Offset -gt $start) { $ue.GetString($Buf, $start, $Offset - $start) } else { '' }
    return @{ String = $str; Offset = $Offset + 2 }
}

function Expect-Bytes([byte[]]$Buf, [int]$Offset, [byte[]]$Expected, [string]$What) {
    if ($Offset + $Expected.Length -gt $Buf.Length) {
        throw "Truncated at offset $Offset while reading $What"
    }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Buf[$Offset + $i] -ne $Expected[$i]) {
            $got = ($Buf[$Offset..($Offset + $Expected.Length - 1)] | ForEach-Object { $_.ToString('X2') }) -join ' '
            $want = ($Expected | ForEach-Object { $_.ToString('X2') }) -join ' '
            throw "Expected $What '$want' at offset $Offset, got '$got'"
        }
    }
}

function Parse-PolEntries {
    param([byte[]]$Bytes)

    if ($Bytes.Length -lt 8) { return @() }
    $sig = [System.Text.Encoding]::ASCII.GetString($Bytes[0..3])
    if ($sig -ne 'PReg') { throw "Not a registry.pol file (signature '$sig')" }

    $entries = @()
    $i = 8
    while ($i -lt $Bytes.Length - 1) {
        while ($i -lt $Bytes.Length - 1) {
            if ($Bytes[$i] -eq 0x5B -and $Bytes[$i + 1] -eq 0x00) { break }
            $i++
        }
        if ($i -ge $Bytes.Length - 1) { break }
        $entryStart = $i

        $end = -1
        for ($j = $i + 2; $j -lt $Bytes.Length - 1; $j++) {
            if ($Bytes[$j] -eq 0x5D -and $Bytes[$j + 1] -eq 0x00) { $end = $j; break }
        }
        if ($end -lt 0) { throw "Unterminated entry starting at offset $i" }

        $body = $Bytes[($entryStart + 2)..($end - 1)]
        $pos = 0

        try {
            $kr = Read-NulTermUtf16 -Buf $body -Offset $pos
            $key = $kr.String; $pos = $kr.Offset
            Expect-Bytes -Buf $body -Offset $pos -Expected ([byte[]](0x3B, 0x00)) -What 'separator after key'
            $pos += 2

            $nr = Read-NulTermUtf16 -Buf $body -Offset $pos
            $name = $nr.String; $pos = $nr.Offset
            Expect-Bytes -Buf $body -Offset $pos -Expected ([byte[]](0x3B, 0x00)) -What 'separator after value name'
            $pos += 2

            if (($pos + 4) -gt $body.Length) { throw 'truncated type' }
            $type = Read-U32LE -Buf $body -Offset $pos
            $pos += 4
            Expect-Bytes -Buf $body -Offset $pos -Expected ([byte[]](0x3B, 0x00)) -What 'separator after type'
            $pos += 2

            if (($pos + 4) -gt $body.Length) { throw 'truncated size' }
            $size = Read-U32LE -Buf $body -Offset $pos
            $pos += 4
            Expect-Bytes -Buf $body -Offset $pos -Expected ([byte[]](0x3B, 0x00)) -What 'separator after size'
            $pos += 2

            if (($pos + $size) -gt $body.Length) { throw 'truncated data' }
            $data = $body[$pos..($pos + $size - 1)]
            $pos += $size

            if ($pos + 1 -lt $body.Length -and $body[$pos] -eq 0x3B -and $body[$pos + 1] -eq 0x00) {
                $pos += 2
            }
        } catch {
            Write-Warning "Skipped malformed entry at offset $entryStart : $_"
            $i = $end + 2
            continue
        }

        $entries += [pscustomobject]@{
            Key     = $key
            Value   = $name
            Type    = $type
            Size    = $size
            Data    = $data
            Offset  = $entryStart
            Length  = ($end - $entryStart + 2)
        }
        $i = $end + 2
    }
    $entries
}

function New-PolEntry {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$ValueName,
        [Parameter(Mandatory)][uint32]$Type,
        [Parameter(Mandatory)][byte[]]$Data
    )

    $ue = [System.Text.Encoding]::Unicode

    $keyBytes = New-Object byte[] ($ue.GetByteCount($Key) + 2)
    [void]$ue.GetBytes($Key, 0, $Key.Length, $keyBytes, 0)
    $keyBytes[$keyBytes.Length - 2] = 0x00
    $keyBytes[$keyBytes.Length - 1] = 0x00

    $nameBytes = New-Object byte[] ($ue.GetByteCount($ValueName) + 2)
    [void]$ue.GetBytes($ValueName, 0, $ValueName.Length, $nameBytes, 0)
    $nameBytes[$nameBytes.Length - 2] = 0x00
    $nameBytes[$nameBytes.Length - 1] = 0x00

    $sizeBytes = New-Object byte[] 4
    [Array]::Copy([BitConverter]::GetBytes([uint32]$Data.Length), $sizeBytes, 4)

    $typeBytes = New-Object byte[] 4
    [Array]::Copy([BitConverter]::GetBytes([uint32]$Type), $typeBytes, 4)

    $sep = New-Object byte[] 2
    $sep[0] = 0x3B; $sep[1] = 0x00

    $bytes = New-Object System.Collections.Generic.List[byte]
    $null = $bytes.Add(0x5B); $null = $bytes.Add(0x00)
    foreach ($b in $keyBytes)  { $null = $bytes.Add($b) }
    foreach ($b in $sep)       { $null = $bytes.Add($b) }
    foreach ($b in $nameBytes) { $null = $bytes.Add($b) }
    foreach ($b in $sep)       { $null = $bytes.Add($b) }
    foreach ($b in $typeBytes) { $null = $bytes.Add($b) }
    foreach ($b in $sep)       { $null = $bytes.Add($b) }
    foreach ($b in $sizeBytes) { $null = $bytes.Add($b) }
    foreach ($b in $sep)       { $null = $bytes.Add($b) }
    foreach ($b in $Data)      { $null = $bytes.Add($b) }
    foreach ($b in $sep)       { $null = $bytes.Add($b) }
    $null = $bytes.Add(0x5D); $null = $bytes.Add(0x00)
    return ,$bytes.ToArray()
}

Write-Host "Patching: $PolPath"

$Bytes = [System.IO.File]::ReadAllBytes($PolPath)
$entries = Parse-PolEntries -Bytes $Bytes
Write-Host "Parsed $($entries.Count) entries from registry.pol"

$edits = @{
    'AUOptions'                      = 4
    'AlwaysAutoRebootAtScheduledTime' = 0
    'NoAUShutdownOption'              = 1
    'NoAutoRebootWithLoggedOnUsers'   = 1
}

# Track which edit keys were found in the source (so we can skip
# appending them as new entries later). Filled by the patching loop.
$foundInSource = @{}

$out = New-Object System.Collections.Generic.List[byte]
foreach ($b in $POL_HEADER) { $null = $out.Add($b) }

foreach ($e in $entries) {
    $editKey = $null
    foreach ($name in $edits.Keys) {
        if ($e.Value -eq $name) { $editKey = $name; break }
    }
    if ($editKey) {
        $newValue = $edits[$editKey]
        $oldValue = if ($e.Type -eq 4 -and $e.Data.Length -ge 4) { [BitConverter]::ToUInt32($e.Data, 0) } else { '<non-dword>' }
        Write-Host "  $editKey : $oldValue -> $newValue"
        $newData = New-Object byte[] 4
        [Array]::Copy([BitConverter]::GetBytes([uint32]$newValue), $newData, 4)
        $newEntry = New-PolEntry -Key $e.Key -ValueName $e.Value -Type $e.Type -Data $newData
        foreach ($b in $newEntry) { $null = $out.Add($b) }
        $foundInSource[$editKey] = $true
    } else {
        for ($i = $e.Offset; $i -lt ($e.Offset + $e.Length); $i++) {
            $null = $out.Add($Bytes[$i])
        }
    }
}

# Append any edits that were NOT in the source (new entries).
foreach ($name in @($edits.Keys)) {
    if ($foundInSource.ContainsKey($name)) { continue }
    $newValue = $edits[$name]
    Write-Host "  $name : (new entry) -> $newValue"
    $key = 'Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $newData = New-Object byte[] 4
    [Array]::Copy([BitConverter]::GetBytes([uint32]$newValue), $newData, 4)
    $newEntry = New-PolEntry -Key $key -ValueName $name -Type 4 -Data $newData
    foreach ($b in $newEntry) { $null = $out.Add($b) }
}

$backup = "$PolPath.bak"
Copy-Item -LiteralPath $PolPath -Destination $backup -Force
Write-Host "Backup: $backup"

$outArray = $out.ToArray()
[System.IO.File]::WriteAllBytes($PolPath, $outArray)
Write-Host "Patched file size: $((Get-Item $PolPath).Length) bytes (was $($Bytes.Length))"

Write-Host ""
Write-Host "Verified values after patch:"
$verify = Parse-PolEntries -Bytes ([System.IO.File]::ReadAllBytes($PolPath))
foreach ($e in $verify) {
    foreach ($name in $edits.Keys) {
        if ($e.Value -eq $name) {
            $val = if ($e.Type -eq 4 -and $e.Data.Length -ge 4) { [BitConverter]::ToUInt32($e.Data, 0) } else { '<non-dword>' }
            Write-Host ("  {0,-40} = {1}" -f $name, $val)
        }
    }
}

Write-Host ""
Write-Host "Done. Copy the patched backup to sysvol on the DC, or re-run Set-WsusGroupPolicy.ps1 to re-import."
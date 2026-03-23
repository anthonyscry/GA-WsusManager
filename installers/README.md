# Installers

Offline installers for WSUS Manager dependencies. Large binaries — gitignored.

## Contents

| File | Size | Description |
|------|------|-------------|
| `SQLEXPRADV_x64_ENU.exe` | ~714 MB | SQL Server 2022 Express with Advanced Services — full offline installer |
| `SSMS-Setup-ENU.exe` | ~473 MB | SQL Server Management Studio — full offline installer (optional) |

## Deploying to SRV01 (Lab)

1. Restore VMs to `Baseline_v2_2026-03-12` checkpoint on triton-ajt
2. Copy installers via SMB from triton-ajt:
   ```powershell
   net use \\SRV01\SQLDBShare /user:SRV01\install P@ssw0rd!
   Copy-Item installers\SSMS-Setup-ENU.exe \\SRV01\SQLDBShare\
   Copy-Item installers\SQLEXPRADV_x64_ENU.exe \\SRV01\SQLDBShare\
   net use \\SRV01\SQLDBShare /delete
   ```
3. Installers go to `C:\WSUS\SQLDB\` on SRV01

## RDP Access

```bash
ssh -N -L 13389:SRV01:3389 triton-ajt
# RDP → localhost:13389
# Credentials: SRV01\install / P@ssw0rd!
```

# Lab Environment

This project can use the shared [Deploy-Lab](../Deploy-Lab/README.md) for Windows testing infrastructure, or its own lab scripts under `lab/`.

**Deploy-Lab** (`C:\projects\Deploy-Lab\`) provides a repeatable 5-VM AutomatedLab environment (DC01, MS01/SQL, MS02, WS01, WS02) with `initial-clean` checkpoints. It is project-agnostic — use it when you need a Windows domain + SQL Server without building a custom lab.

## Quick reference

| Resource | Location |
|---|---|
| Deploy-Lab docs | `C:\projects\Deploy-Lab\README.md` |
| This project's lab scripts | `lab/` |
| Reset to baseline | `C:\projects\Deploy-Lab\Restore-Checkpoints.ps1` |
| Lab builder | `C:\projects\Deploy-Lab\New-DeployLab.ps1` |

See `C:\projects\Deploy-Lab\README.md` for full lab setup, VM inventory, credentials, and management instructions.

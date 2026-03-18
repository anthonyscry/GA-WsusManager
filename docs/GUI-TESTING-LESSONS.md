# GUI Automation Testing — Lessons Learned

Real-world lessons from automating a WPF desktop application (PowerShell/WPF) on Windows Server VMs via COM UI Automation. Tested on headless VMs accessed through SSH tunnels and RDP sessions.

---

## 1. Accessing GUIs on Headless VMs

### The Problem
Headless VMs have no physical console. COM UIA's `RootElement` cannot find GUI windows without an interactive desktop session. Running scripts via `Invoke-Command -VMName` runs in Session 0 (services), which has no desktop.

### The Solution
Use **scheduled tasks with the `/IT` (interactive) flag** to run scripts in the user's desktop session:

```cmd
schtasks /Create /TN "MyGuiTest" `
    /TR "powershell.exe -ExecutionPolicy Bypass -File C:\Tests\GuiTest.ps1" `
    /SC ONCE /ST 23:59 `
    /RU "DOMAIN\User" /RP "Password" `
    /RL HIGHEST /IT /F

schtasks /Run /TN "MyGuiTest"
```

- `/IT` is **mandatory** — without it, the task runs in the background with no desktop access
- The user must have an active RDP session (Session 1+) — Session 0 won't work
- The session must be in `Active` state, not `Disc` (disconnected)

### Keeping Sessions Active
After connecting via RDP, the session stays active even after disconnecting `xfreerdp`. But `SendKeys` stops working if the session goes to `Disc` state. Check with:

```powershell
query user
```

Reconnect briefly before running tests if the session shows `Disc`.

---

## 2. RDP Through SSH Tunnels

When the target VM is behind a Hyper-V host:

```bash
# Create tunnel (runs in background)
ssh -fN -L 13390:192.168.50.21:3389 triton-ajt

# Connect RDP through tunnel
DISPLAY=:0 xfreerdp /v:127.0.0.1:13390 \
    /u:"SRV02\Install" /p:"P@ssw0rd!" \
    /cert:ignore /size:1024x768 /bpp:16
```

**Key points:**
- Use `/bpp:16` to reduce bandwidth on slow lab networks
- Use `/cert:ignore` for self-signed certs on lab VMs
- The tunnel must exist before RDP can connect
- Use `pgrep -f "13390"` to verify tunnel is alive

---

## 3. COM UIA vs FlaUI vs SendKeys

### COM UIA (System.Windows.Automation)
**Best for:** Finding elements, reading properties, structured interaction

```powershell
Add-Type -AssemblyName UIAutomationClient
$root = [System.Windows.Automation.AutomationElement]::RootElement

# Find by AutomationId
$btn = $root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
        "BtnInstall"
    )
)

# Click via InvokePattern
$pattern = $btn.GetCurrentPattern(
    [System.Windows.Automation.InvokePattern]::Pattern
)
$pattern.Invoke()
```

**Pros:** Reliable element finding, works across frameworks
**Cons:** Cannot type into some controls, screenshots fail from scheduled tasks

### ValuePattern for Text Entry
WPF `TextBox` and `PasswordBox` both support `ValuePattern`:

```powershell
$valPattern = $element.GetCurrentPattern(
    [System.Windows.Automation.ValuePattern]::Pattern
)
$valPattern.SetValue("my password")
```

This is the most reliable way to set text in WPF controls. Falls back to `TextPattern` or `SendKeys` if not available.

### SendKeys — Last Resort
`[System.Windows.Forms.SendKeys]::SendWait()` requires the control to have focus and the window to be in the foreground. Unreliable from scheduled tasks.

### Screenshots from Scheduled Tasks
**This will fail** from a scheduled task:
```powershell
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
# Error: "The handle is invalid"
```

The scheduled task's process doesn't have access to the desktop DC (device context), even with `/IT`. **Workarounds:**
1. Use a separate lightweight screenshot tool (e.g., `nircmd.exe cmdwait 1000 savescreenshot`)
2. Accept no screenshots and verify via service checks and log files
3. Use `tscon` to attach the session before capturing

---

## 4. PowerShell Direct (Hyper-V) vs WinRM

### PowerShell Direct
```powershell
$cred = New-Object PSCredential("VM\User", (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force))
Invoke-Command -VMName SRV02 -Credential $cred -ScriptBlock { ... }
```

**Pros:** Works even without network, no WinRM setup needed
**Cons:** Needs Hyper-V module + admin on host, file transfer requires `New-PSSession`

### File Transfer with PowerShell Direct
```powershell
# Upload (two-hop for large files)
$s = New-PSSession -VMName SRV02 -Credential $cred
Copy-Item -Path "C:\local\file.exe" -ToSession $s -Destination "C:\target\" -Force
Remove-PSSession $s

# Download
$s = New-PSSession -VMName SRV02 -Credential $cred
Copy-Item -FromSession $s -Path "C:\source\*" -Destination "C:\local\" -Force
Remove-PSSession $s
```

**Critical:** Cannot use `-FromSession` and `-ToSession` on the same `Copy-Item` command. For two-hop transfers (VM1 → Host → VM2), pull to host first, then push.

### Shell Escaping Through SSH
PowerShell commands through SSH have brutal escaping. Variables like `$cred` get eaten by bash. **Solution:** Write the script to a file, `scp` it, then execute it:

```bash
# WRONG — escaping nightmare
ssh host 'powershell -Command "$cred = New-Object ..."'

# RIGHT — script file approach
scp script.ps1 host:C:/Temp/script.ps1
ssh host 'powershell -ExecutionPolicy Bypass -File C:\Temp\script.ps1'
```

---

## 5. Long-Running Operations in GUI Tests

### Polling for Completion
Don't just `Start-Sleep 600` and hope. Poll for observable state changes:

```powershell
$maxWait = 25  # minutes
$startTime = Get-Date

while (((Get-Date) - $startTime).TotalMinutes -lt $maxWait) {
    Start-Sleep -Seconds 30
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

    # Check if operation button re-enabled (operation done)
    $btn = Find-Element $mainWindow "BtnInstall" -timeout 5
    if ($btn) {
        $isEnabled = $btn.GetCurrentPropertyValue(
            [System.Windows.Automation.AutomationElement]::IsEnabledProperty
        )
        if ($isEnabled) {
            Write-Log "Complete at ${elapsed}min"
            break
        }
    }

    # Check if process crashed
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) {
        Write-Log "Process exited unexpectedly"
        break
    }
}
```

### Verifying Results Without Screenshots
When screenshots fail, verify via:
- **Service status:** `Get-Service 'MSSQL$SQLEXPRESS'` → Running
- **Registry keys:** `Test-Path "HKLM:\SOFTWARE\..."` → True
- **Install logs:** `Get-Content "C:\Logs\install.log" -Tail 20`
- **File existence:** `Test-Path "C:\Program Files\..."` → True
- **Port listening:** `Test-NetConnection -ComputerName localhost -Port 1433`

---

## 6. VM State Management

### Snapshots Are Your Friend
Before any destructive test, snapshot the VM:

```powershell
Checkpoint-VM -VMName SRV02 -SnapshotName "Pre-GuiTest-$(Get-Date -Format 'yyyyMMdd-HHmm')"
```

Revert when things go wrong:

```powershell
Restore-VM -VMName SRV02 -SnapshotName "Pre-GuiTest-..." -Confirm:$false
```

### Detecting Existing Installs
The install script's `$sqlInstalled` check uses both service and registry:

```powershell
$sqlService = Get-Service 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
$sqlInstanceKey = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
$sqlInstalled = ($null -ne $sqlService) -or
    (Test-Path $sqlInstanceKey -and
     (Get-ItemProperty $sqlInstanceKey).SQLEXPRESS)
```

### Cleaning Partial Installs
Failed installs leave behind partial state that causes SQL setup to skip (exit 0 immediately). Clean:
1. `C:\Program Files\Microsoft SQL Server\160\` (partial install dir)
2. `C:\Program Files\Microsoft SQL Server\170\Setup Bootstrap\` (setup logs)
3. Extracted installer files (`SQL2022EXP/`)
4. Configuration file (`ConfigurationFile.ini`)
5. Encrypted password file (`sa.encrypted`)

---

## 7. Password Handling in GUI Automation

### Environment Variable Pattern
Never pass passwords on the command line (visible in process listings):

```powershell
# GUI side: set env var, reference via $env: in the command string
$env:WSUS_INSTALL_SA_PASSWORD = $saPassword
$command = "& '$script' -SaPassword `$env:WSUS_INSTALL_SA_PASSWORD -NonInteractive"
# The backtick-dollar escapes $ so it expands in the child process, not the parent
```

### ValuePattern for PasswordBox
WPF `PasswordBox` exposes `ValuePattern` — use it instead of `SendKeys`:

```powershell
$valPattern = $passwordBox.GetCurrentPattern([ValuePattern]::Pattern)
$valPattern.SetValue("MyP@ssw0rd!")
```

Verify the control class is `PasswordBox` before attempting.

---

## 8. Testing on Air-Gapped Networks

### No Internet = No Downloads
SQL Express installer cannot download components during install. Add to config:

```ini
UPDATEENABLED="0"
```

This prevents SQL setup from checking Windows Update for patches during installation. Without it, setup may hang or fail silently on isolated networks.

### File Sizes Matter
- `SQLEXPR_x64_ENU.exe` (Basic, ~255MB) — does NOT work as self-extracting archive
- `SQLEXPRADV_x64_ENU.exe` (Advanced, ~714MB) — works, supports all features
- Always use the Advanced edition for automated installs

---

## 9. Anti-Patterns to Avoid

### ❌ Don't hardcode installer filenames
```powershell
# WRONG — breaks when filename changes
$installer = Join-Path $path "SQLEXPRADV_x64_ENU.exe"

# RIGHT — flexible candidates
$installerCandidates = @("SQLEXPRADV_x64_ENU.exe", "SQLEXPR_x64_ENU.exe")
foreach ($name in $installerCandidates) {
    $p = Join-Path $path $name
    if (Test-Path $p) { $installer = $p; break }
}
```

### ❌ Don't assume exit codes
```powershell
# WRONG — ExitCode can be null if process is killed
if ($proc.ExitCode -ne 0) { throw }

# RIGHT — null-safe check
if ($null -ne $proc.ExitCode -and $proc.ExitCode -ne 0) { throw }
$proc.WaitForExit()  # Ensure ExitCode is populated
```

### ❌ Don't suppress reboots with invalid parameters
```ini
# WRONG — SQL Server 2022+ rejects this
SUPPRESSREBOOT="True"    # Error: "The setting 'SUPPRESSREBOOT' specified is not recognized"
SkipRules="RebootRequiredCheck"  # Also rejected in config file

# RIGHT — if reboots are a problem, handle exit code 3010 (reboot required)
# The script should treat 3010 as success, not failure
```

### ❌ Don't use `-FromSession` and `-ToSession` together
```powershell
# WRONG — this doesn't work
Copy-Item -FromSession $s1 -ToSession $s2 -Path "file" -Destination "dest"

# RIGHT — two-hop through the host
Copy-Item -FromSession $s1 -Path "file" -Destination "C:\Temp\"
Copy-Item -Path "C:\Temp\file" -ToSession $s2 -Destination "dest\"
```

---

## 10. Test Infrastructure Pattern

### Recommended Project Structure
```
Tests/
├── FlaUI.Tests.ps1              # Unit tests (71 tests, run on dev machine)
├── FlaUITestHarness/
│   └── FlaUITestHarness.psm1    # COM UIA helper module
└── GuiInstallTest.ps1           # E2E install test (run on VM)
```

### Recommended Test Execution Flow
1. **Local unit tests** (FlaUI.Tests.ps1) — fast, no VM needed
2. **VM E2E test** (GuiInstallTest.ps1) — scheduled task via SSH tunnel
3. **Verification** — check logs + service status + registry

### Deployment Script Pattern
Write a deploy script that handles everything in one shot:

```powershell
# 1. Kill existing processes
# 2. Clean old artifacts (logs, screenshots, partial installs)
# 3. Upload test files via Copy-Item -ToSession
# 4. Set up RDP session (xfreerdp via SSH tunnel)
# 5. Create + run scheduled task with /IT
# 6. Poll for completion (check result file)
# 7. Pull logs + screenshots
# 8. Verify services
```

---

## Quick Reference Cheat Sheet

| Task | Command |
|------|---------|
| Find element by AutomationId | `$root.FindFirst([TreeScope]::Descendants, [PropertyCondition]::new([AutomationElement]::AutomationIdProperty, "id"))` |
| Click button | `$btn.GetCurrentPattern([InvokePattern]::Pattern).Invoke()` |
| Set text in TextBox | `$box.GetCurrentPattern([ValuePattern]::Pattern).SetValue("text")` |
| Check if enabled | `$el.GetCurrentPropertyValue([AutomationElement]::IsEnabledProperty)` |
| Run as interactive task | `schtasks /Create ... /IT /F && schtasks /Run /TN "Name"` |
| PowerShell Direct | `Invoke-Command -VMName VM -Credential $cred -ScriptBlock { }` |
| Copy file to VM | `$s = New-PSSession -VMName VM -Credential $cred; Copy-Item -ToSession $s -Path local -Destination remote` |
| Check RDP sessions | `query user` |
| Check service | `Get-Service 'Name' -ErrorAction SilentlyContinue \| Select Status` |
| Snapshot VM | `Checkpoint-VM -VMName VM -SnapshotName "Pre-Test"` |
| Revert VM | `Restore-VM -VMName VM -SnapshotName "Pre-Test" -Confirm:\$false` |

---

## 11. WPF Grid Panels Don't Expose AutomationId to UIA

### The Problem
WPF `Grid` elements with `AutomationProperties.AutomationId` set in XAML are NOT findable by COM UIA. Searching for `DashboardPanel`, `InstallPanel`, `HelpPanel`, `HistoryPanel`, `OperationPanel`, or `LogPanel` by AutomationId always returns null — despite the attribute being set in XAML.

### The Exception
`ScrollViewer` elements DO work. `AboutPanel` (which is a `ScrollViewer`) is the only panel reliably found by AutomationId.

### The Solution
Verify panel visibility by probing for a unique child element instead:

```powershell
# WRONG — Grid AutomationId not exposed to COM UIA
$panel = Find-El $mw "DashboardPanel"

# RIGHT — probe for a unique child
$panelVisible = $null -ne (Find-El $mw "Card1Value")    # Dashboard
$panelVisible = $null -ne (Find-El $mw "InstallPathBox") # Install
$panelVisible = $null -ne (Find-El $mw "HelpText")       # Help
$panelVisible = $null -ne (Find-El $mw "BtnRefreshHistory") # History
$panelVisible = $null -ne (Find-El $mw "AboutPanel")     # About (ScrollViewer — works)
```

### Root Cause
WPF's `Grid` control does not implement `AutomationPeer` for AutomationId by default. `ScrollViewer` does. If you need UIA-discoverable panels, wrap them in `ScrollViewer` or use `UserControl` with explicit `AutomationPeer`.

---

## 12. SendKeys Hangs in Scheduled Tasks

### The Problem
`[System.Windows.Forms.SendKeys]::SendWait("^d")` hangs indefinitely when called from a scheduled task context, even with `/IT` flag and an active desktop session. `SetForegroundWindow` succeeds (returns true), but `SendKeys` blocks forever.

### Impact
Keyboard shortcuts (Ctrl+D, Ctrl+S, Ctrl+H, etc.) **cannot be tested from scheduled tasks**. Only UIA `InvokePattern` and `ValuePattern` interactions work.

### Workaround
If you must test keyboard shortcuts, use a local PowerShell session (not a scheduled task). For automated CI pipelines, skip keyboard shortcut tests or use a framework that supports raw input injection (e.g., `InputSimulator` via C# interop).

---

## 13. Dialog Interactions Corrupt the UIA Tree

### The Problem
Opening and closing WPF dialogs (especially Settings) from a scheduled task's UIA session permanently corrupts the UIA tree. After closing a dialog via `WindowPattern.Close()`, ALL subsequent `Find-Element` calls fail — even with fresh `Get-MainWindow()` calls from `RootElement`. May also trigger VM shutdown.

### The Solution
**Test order matters.** Structure your test suite so that destructive interactions happen last:

1. **Read-only tests first** — dashboard data, element visibility, enabled states
2. **Panel navigation second** — click nav buttons, verify child elements, return to dashboard
3. **Dialog state-only checks third** — find buttons, verify enabled/disabled, but DON'T click
4. **Any dialog open/close LAST** — or skip entirely if not critical

```powershell
# Test order in production:
# CAT 1: Dashboard cards (read-only)
# CAT 2: Panel navigation (click nav, verify child, return)
# CAT 3: Dialog buttons (state check only — no clicking)
# CAT 4-8: Deep panel checks
# CAT 9: Settings (SKIPPED — known to corrupt UIA tree)
# CAT 10: Button inventory (read-only)
```

---

## 14. Active Desktop Session Required

### The Problem
After a VM reboot, `RootElement.Children` returns 0 items without an active user session. Scheduled tasks run but cannot see any desktop windows.

### The Solution
Establish an RDP session (even briefly) before running tests. Disconnected sessions (`Disc` state) work fine — you don't need to keep the RDP window open.

```powershell
# Check sessions
query user

# If no active session, reconnect
ssh -fN -L 13390:192.168.50.21:3389 triton-ajt
DISPLAY=:0 xfreerdp /v:127.0.0.1:13390 /u:"SRV02\Install" /p:"P@ssw0rd!" /cert:ignore /size:1024x768 /bpp:16
# Close after login — session stays active in "Disc" state
```

---

## 15. Phantom Window Detection

### The Problem
When searching for modal dialogs, you'll find windows that aren't your app's dialogs: `ConsoleWindowClass` (the test script's own PowerShell window), `Shell_TrayWnd` (taskbar), `Progman` (desktop), and windows with empty `Name` properties.

### The Solution
Filter aggressively when enumerating top-level windows:

```powershell
$allWindows = $root.FindAll([TreeScope]::Children, [Condition]::TrueCondition)
$dialogs = $allWindows | Where-Object {
    $_.Current.ClassName -ne "ConsoleWindowClass" -and
    $_.Current.ClassName -ne "Shell_TrayWnd" -and
    $_.Current.ClassName -ne "Progman" -and
    -not [string]::IsNullOrEmpty($_.Current.Name)
}
```

---

## 16. Test Suite Design Patterns

### Pattern: Return-to-Dashboard After Each Test
Always return to a known state (dashboard) after each navigation test. This prevents cascading failures where a test expects Dashboard but the app is showing Install.

```powershell
function Go-Dash {
    $mw = Get-MainWindow -timeout 10
    if ($mw) {
        $b = Find-El $mw "BtnDashboard" -timeout 5
        if ($b) { Click-El $b }
    }
    Start-Sleep -Seconds 2
    return (Get-MainWindow -timeout 10)
}
```

### Pattern: State-Only vs Interactive Tests
Split your test catalog into two tiers:

| Tier | What | Risk |
|------|------|------|
| **State checks** | Element found, enabled, value readable | Zero risk |
| **Interactive** | Click button, set text, close dialog | May corrupt UIA tree |

Run all state checks first. Run interactive tests last, and only if needed.

### Pattern: Graceful Degradation with Warnings
Not every element must be found. Use WARN for non-critical missing elements and FAIL for critical ones:

```powershell
# Critical — app is broken without this
if (-not (Find-El $mw "Card1Value")) { TF "Services card" "not found" }

# Non-critical — nice to have
if (-not (Find-El $mw "InternetStatusText")) { TW "Internet status" "not found" }
```

### Pattern: Timeouts and Retries
COM UIA is inherently asynchronous. Never assume an element exists immediately after a click. Use polling with timeouts:

```powershell
function Find-El($parent, $automationId, $timeout = 10) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $timeout) {
        try {
            $el = $parent.FindFirst([TreeScope]::Descendants,
                [PropertyCondition]::new([AutomationElement]::AutomationIdProperty, $automationId))
            if ($null -ne $el) { return $el }
        } catch {}
        Start-Sleep -Milliseconds 300
    }
    return $null
}
```

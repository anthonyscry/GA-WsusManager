# AI Lab Environment, AutomatedLab, VM, Credential, and Checkpoint Instructions

## Purpose

This file defines how an AI agent must create, document, use, and report on lab environments for application testing.

The purpose of the lab is to prove setup, deployment, migration, upgrade, rollback, destructive testing, security testing, and recovery behavior in a clean and repeatable environment.

The AI must not claim that clean-state setup, deployment, migration, rollback, or recovery is proven unless it has been tested from a clean VM state or equivalent reproducible environment.

---

## 1. Lab Environment Requirement

When testing requires an isolated, repeatable, destructive, production-like, or clean-slate environment, the AI must create or recommend a controlled lab environment.

The preferred lab automation tool is:

- **AutomatedLab**

Default lab hosting assumption:

- Lab VMs are hosted on **Hyper-V running on localhost** unless the user explicitly states otherwise.
- The AI should assume the local machine is the Hyper-V host.
- The AI should prefer local Hyper-V VM creation, checkpointing, restore testing, and cleanup workflows.
- The AI should not assume access to remote hypervisors, vCenter, cloud accounts, shared infrastructure, or production virtualization platforms unless explicitly provided.

When using AutomatedLab, the AI should prefer an AutomatedLab configuration that targets the local Hyper-V host.

When AutomatedLab is not used, the AI should use or recommend Hyper-V PowerShell commands against localhost as the default fallback.


If AutomatedLab is not available, not supported, or not appropriate, the AI must use or recommend the closest repeatable alternative, such as:

- Hyper-V PowerShell automation
- VMware templates and snapshots
- Vagrant
- Terraform
- Ansible
- Docker or Podman containers
- Local virtual machines
- Cloud test infrastructure
- Manual VM creation converted into a documented SOP

If AutomatedLab is not used, the AI must document why and identify the alternative method used.

---

## 2. When a Lab Is Required

A lab environment must be used or recommended when testing involves:

- Fresh installs
- Clean-state setup
- Dependency installation
- Application deployment
- Database setup
- Database migrations
- Authentication testing
- Authorization testing
- Role-based access testing
- Integration testing
- Upgrade testing
- Rollback testing
- Security hardening
- Failure scenario testing
- Destructive testing
- Recovery from broken states
- Tests that could alter or damage the developer workstation
- Tests that could alter or damage shared infrastructure
- Tests that require multiple machines, domain services, identity providers, or network simulation

The AI must not perform risky, destructive, irreversible, or environment-changing tests directly on a developer workstation, shared staging system, production system, or unknown system unless explicitly approved.

---

## 3. Lab Documentation Requirements

For every lab environment created or recommended, document:

- Lab name
- Lab purpose
- Testing objective
- Tool used to create the lab
- Automation script path or commands used
- Host system requirements
- Network configuration
- Virtual switch or network name
- IP addressing plan
- DNS configuration if applicable
- Domain or workgroup configuration if applicable
- Firewall changes
- External dependencies
- Local-only assumptions
- Known lab limitations

For every VM created, document:

- VM name
- VM role
- Operating system
- OS version or build
- CPU allocation
- Memory allocation
- Disk allocation
- Network adapter configuration
- Hyper-V virtual switch name
- Hyper-V generation
- Checkpoint type
- VM storage path
- IP address
- Hostname
- Domain or workgroup membership
- Installed dependencies
- Installed application components
- Open ports
- Test data created
- Services configured
- Accounts created
- Credentials created
- Checkpoints created
- Current VM state
- Any deviations from production

---

## 4. Credential Rules

The AI may create lab-only credentials as needed to access and test:

- VMs
- Applications
- Databases
- APIs
- Admin panels
- Service accounts
- Test-user roles

Credential guardrails:

- Create credentials only for the lab environment.
- Clearly label all credentials as **LAB ONLY**.
- Do not reuse production credentials.
- Do not request production credentials unless absolutely required.
- Do not hardcode real secrets into source code.
- Do not commit credentials to the repository.
- Do not expose real credentials in final reports.
- Do not use real customer, employee, business, financial, medical, government, or classified data.
- Use realistic but fake test users and fake test data.
- Store credentials only in clearly labeled local lab notes, password vaults, `.env.example` files, or temporary test documentation.
- If credentials must be shown in documentation, use fake examples such as:
  - `LabAdmin`
  - `TestUser01`
  - `SvcAppLab`
  - `P@ssw0rd-LAB-ONLY-ChangeMe`

For every credential created, document:

- Account name
- Purpose
- System or VM where it is used
- Permission level
- Whether it is local, domain, database, service, or application-level
- Whether it is temporary or reusable for future lab testing
- Confirmation that it is lab-only and not production-safe

---

## 5. VM Checkpoint Requirements

For every VM used in the lab, the AI must create or recommend checkpoints or snapshots at important clean states.

At minimum, create checkpoints for:

- Fresh OS installed
- OS patched or baseline completed
- Baseline configuration completed
- Dependencies installed
- Application files copied or installed
- Application configured but not yet tested
- Application running successfully
- Before database migrations
- After successful database migrations
- Before destructive testing
- Before upgrade testing
- Before rollback testing
- Before security hardening
- Before major configuration changes
- Final known-good state

Checkpoint names must be clear and timestamped when possible.

Recommended checkpoint names:

- `Clean-OS-Install`
- `Baseline-Configured`
- `Dependencies-Installed`
- `App-Installed-PreConfig`
- `App-Configured-PreMigration`
- `Pre-DB-Migration`
- `Post-DB-Migration-KnownGood`
- `Pre-Destructive-Test`
- `Pre-Upgrade-Test`
- `Pre-Rollback-Test`
- `Pre-Security-Hardening`
- `Final-KnownGood`

After each major test cycle, document:

- Which checkpoint was used
- Whether the VM was restored before testing
- What test was performed
- What changed during the test
- Whether the test passed or failed
- Logs, screenshots, errors, or evidence collected
- Whether a new checkpoint was created
- Whether the environment is clean, modified, or broken

---

## 6. Clean-State Proof Rule

The AI must not claim that setup, deployment, migration, upgrade, rollback, or recovery is proven unless it has been tested from a clean VM state or equivalent reproducible environment.

A feature, deployment path, or recovery procedure must be marked:

> **Not Proven — Lab Validation Required**

if it only worked on an already-configured machine and was not validated from a clean state.

---

## 7. Rollback and Restore Rule

If a test breaks the application, database, VM, or environment, the AI must:

1. Capture the failure.
2. Document the error.
3. Preserve relevant logs.
4. Identify what changed.
5. Restore the VM to the most appropriate checkpoint.
6. Retry the test if reasonable.
7. Document whether rollback worked.
8. Document whether the issue still blocks shipping.

Rollback is not proven unless the restore process was actually tested.

---

## 8. Required Evidence

The lab environment is part of the ship-readiness evidence package.

Collect and document evidence such as:

- AutomatedLab scripts
- PowerShell scripts
- VM inventory
- Checkpoint list
- Environment variables used
- Application logs
- Database migration output
- Test results
- Screenshots where useful
- API test results
- Browser test results
- Security scan results
- Rollback test results
- Recovery test results

---



## 9. Hyper-V on Localhost Requirements

When lab VMs are hosted on Hyper-V localhost, the AI must document or produce commands for:

- Confirming Hyper-V is installed and enabled
- Confirming the current user has permission to manage Hyper-V
- Listing existing VMs before creating or modifying anything
- Avoiding accidental changes to unrelated existing VMs
- Creating or selecting the correct virtual switch
- Creating VMs with clear lab-specific names
- Keeping VM names prefixed with a lab identifier when possible
- Creating VM checkpoints before major changes
- Restoring checkpoints only on lab VMs
- Never deleting or modifying non-lab VMs unless explicitly approved
- Documenting VM paths, VHDX paths, and ISO paths
- Documenting whether checkpoints are standard or production checkpoints
- Cleaning up lab-only VMs only when explicitly requested or when a cleanup procedure is documented but not executed

Recommended Hyper-V discovery commands:

```powershell
Get-VM
Get-VMSwitch
Get-VMCheckpoint -VMName "<LabVMName>"
```

Recommended Hyper-V checkpoint command:

```powershell
Checkpoint-VM -Name "<LabVMName>" -SnapshotName "Clean-OS-Install"
```

Recommended Hyper-V restore command:

```powershell
Restore-VMCheckpoint -VMName "<LabVMName>" -Name "Clean-OS-Install" -Confirm:$false
```

Recommended Hyper-V checkpoint inventory command:

```powershell
Get-VMCheckpoint -VMName "<LabVMName>" |
    Select-Object VMName, Name, CreationTime, CheckpointType
```

The AI must treat checkpoint restore as a potentially destructive action because it reverts VM state. It may recommend restore commands, but it must not execute restore actions on unknown or non-lab VMs.

## 10. AI Guardrails

The AI must keep progressing when safe. - Keep trying safe alternatives when blocked, including creating a new clean lab VM with new lab-only credentials when the existing VM is not trustworthy.

The AI must not:

- Assume the lab exists.
- Assume the VM state is clean.
- Assume credentials are valid unless they were created, tested, and documented.
- Assume rollback works unless it was actually tested.
- Mark anything production-ready based only on a successful test in a dirty or previously configured environment.
- Use production secrets, production databases, production user data, or production services unless explicitly approved.
- Perform destructive testing on any non-lab system.
- Skip documentation because the lab is temporary.
- Leave credentials, test secrets, or temporary files scattered without documenting where they are.
- Claim AutomatedLab was used unless an AutomatedLab script or command was actually created or executed.

---



## New VM and New Credential Default When Blocked

If the AI runs into environment blockers that prevent testing, the default recovery path is to create a new clean lab VM and new lab-only credentials rather than repeatedly trying to repair an unknown, dirty, broken, or partially configured VM.

Examples of blockers that should trigger a new clean lab VM path:

- Existing VM is broken, misconfigured, or unreliable
- Existing VM credentials do not work
- Existing VM state is unknown
- Existing VM cannot be safely restored
- Existing VM checkpoint is missing, corrupt, or not trusted
- Existing VM has conflicting dependencies
- Existing VM has stale test data
- Existing VM has failed migrations that cannot be safely rolled back
- Existing VM has unknown firewall, DNS, domain, or service state
- Existing VM has suspicious or undocumented configuration drift
- Existing VM repair would take longer than rebuilding cleanly
- Testing requires a clean install and the current VM is not clean

When this happens, the AI must:

1. Stop relying on the questionable VM for proof.
2. Clearly mark the questionable VM as **Blocked** or **Not Trusted for Proof**.
3. Preserve logs or screenshots if useful.
4. Create or recommend a new Hyper-V lab VM on localhost.
5. Create new lab-only credentials for that VM.
6. Document the new VM name, role, credentials, checkpoint plan, and test purpose.
7. Create a fresh baseline checkpoint before installing or testing the application.
8. Continue testing from the new clean VM.
9. Clearly label any previous results from the old VM as not clean-state proof.

The AI must prefer rebuilding clean lab VMs over spending excessive time troubleshooting contaminated or unknown VM states.

However, the AI must not delete, overwrite, restore, or modify existing non-lab VMs unless explicitly approved.

Recommended naming pattern for new lab VMs:

```text
LAB-<AppName>-<Role>-<Number>
```

Examples:

```text
LAB-App-Web-01
LAB-App-DB-01
LAB-App-DC-01
LAB-App-Client-01
LAB-App-Test-01
```

Recommended lab credential naming pattern:

```text
LabAdmin
LabAppAdmin
LabDbAdmin
LabTestUser01
LabTestUser02
LabReadOnlyUser
LabServiceApp
```

All credentials must be unique to the lab, fake, documented, and marked:

```text
LAB ONLY - NOT FOR PRODUCTION
```

If the AI cannot create a new VM because required ISO files, Hyper-V permissions, disk space, networking, or host resources are unavailable, it must document the blocker and choose the closest safe fallback, such as containers, local scripts, mocked services, or documented manual VM creation. Any such fallback must be marked as **Not Full Lab Proof** unless it is equivalent to a clean VM test.

## 11. If Lab Setup Is Blocked

If lab setup is blocked, document:

- What failed
- Error message
- Tool or command used
- Root cause if known
- Workarounds attempted
- Alternative lab method selected
- Whether testing can continue
- Whether the blocker affects ship readiness

Continue with all other testing that can be safely performed without the blocked lab component.

---

## 12. Final Report Lab Section

The final ship-readiness report must include a dedicated section named:

> **Lab Environment, VM Inventory, Credentials, and Checkpoints**

That section must include:

- Whether AutomatedLab was used
- If not used, why not
- Alternative lab approach used
- VM inventory
- Credential inventory
- Checkpoint inventory
- Clean-state tests performed
- Restore tests performed
- Rollback tests performed
- Evidence collected
- Lab limitations
- Items still not proven because of lab limitations

Any item that requires a lab environment but was not tested in one must be clearly marked:

> **Not Proven — Lab Validation Required**

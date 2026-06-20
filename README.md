# Windows Autopilot Diagnostics Toolkit

A read-only PowerShell toolkit for collecting Windows Autopilot, Entra ID, Intune enrolment, MDM, provisioning, and device-readiness evidence.

## Features

- Windows edition, build, hardware, TPM, Secure Boot, and firmware context
- `dsregcmd /status` capture and join-state summary
- Autopilot registry and provisioning information
- MDM enrolment registry inventory
- DeviceManagement-Enterprise-Diagnostics-Provider event collection
- Autopilot and provisioning event logs
- Intune Management Extension service and log context
- Network reachability tests to core Microsoft enrolment endpoints
- CSV, JSON, HTML, and text outputs
- Automatic redaction of common token and identifier patterns in HTML output

## Usage

Run from an elevated PowerShell console:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\src\Get-AutopilotDiagnostics.ps1
```

Specify an output folder and event window:

```powershell
.\src\Get-AutopilotDiagnostics.ps1 -OutputPath C:\Temp\AutopilotReport -Hours 72
```

## Safety

The toolkit is diagnostic-only. It does not enrol, unenrol, join, unjoin, reset, wipe, sync, or modify the device.

## Validation

Test on an Entra-joined Intune-managed device, a workgroup device, and a lab device with a failed enrolment event.

## Author

Dewald Pretorius — L2 IT Support Engineer

#requires -Version 5.1
<#
.SYNOPSIS
    Guarded Windows Autopilot and Intune client recovery toolkit.
.DESCRIPTION
    Diagnoses by default and performs safe local recovery actions for Intune
    Management Extension, MDM services, EnterpriseMgmt scheduled tasks, DNS and
    the current user's Entra Primary Refresh Token.
.NOTES
    Created by Dewald Pretorius - L2 IT Support Engineer.
    This script never unenrols, unjoins, resets, wipes or removes the device.
#>

[CmdletBinding()]
param(
    [switch]$RepairAllSafe,
    [switch]$RestartIntuneManagementExtension,
    [switch]$RestartMdmServices,
    [switch]$TriggerMdmSync,
    [switch]$RefreshPrimaryRefreshToken,
    [switch]$FlushDns,
    [switch]$ArchiveIntuneLogs,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ExitCode = 0

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "Autopilot_Safe_Recovery_$Stamp"
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$LogPath = Join-Path $OutputPath 'recovery.log'
$BackupPath = Join-Path $OutputPath 'backup'
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DRYRUN')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN'    { Write-Host $Message -ForegroundColor Yellow }
        'ERROR'   { Write-Host $Message -ForegroundColor Red }
        'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        'DRYRUN'  { Write-Host "DRY RUN: $Message" -ForegroundColor Cyan }
        default   { Write-Host $Message }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'This recovery action requires an elevated PowerShell session.'
    }
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$HighImpact
    )
    if ($DryRun -or $Yes) { return $true }
    $token = if ($HighImpact) { 'REPAIR' } else { 'YES' }
    return (Read-Host "$Message Type $token to continue") -eq $token
}

function Get-DsRegText {
    try { return (& dsregcmd.exe /status 2>&1 | Out-String) } catch { return $null }
}

function Get-DsRegValue {
    param(
        [string]$Text,
        [string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, "(?m)^\s*$([regex]::Escape($Name))\s*:\s*(.+?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-EnterpriseMgmtTasks {
    return @(
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $_.TaskPath -like '\Microsoft\Windows\EnterpriseMgmt\*'
        }
    )
}

function Get-SyncCandidateTasks {
    return @(
        Get-EnterpriseMgmtTasks | Where-Object {
            $_.State -ne 'Disabled' -and
            $_.TaskName -match '(?i)PushLaunch|Schedule #3 created by enrollment client|OMADMClient|Reconcile'
        }
    )
}

function Save-State {
    param([Parameter(Mandatory)][string]$Stage)

    $dsreg = Get-DsRegText
    if ($dsreg) {
        $dsreg | Set-Content -LiteralPath (Join-Path $OutputPath "dsregcmd-$Stage.txt") -Encoding UTF8
    }

    $tasks = @(Get-EnterpriseMgmtTasks)
    $taskRows = foreach ($task in $tasks) {
        $info = Get-ScheduledTaskInfo -InputObject $task -ErrorAction SilentlyContinue
        [pscustomobject]@{
            TaskName = $task.TaskName
            TaskPath = $task.TaskPath
            State = $task.State
            LastRunTime = if ($info) { $info.LastRunTime } else { $null }
            LastTaskResult = if ($info) { $info.LastTaskResult } else { $null }
            NextRunTime = if ($info) { $info.NextRunTime } else { $null }
        }
    }

    $endpoints = foreach ($endpoint in @(
        'login.microsoftonline.com',
        'device.login.microsoftonline.com',
        'enterpriseregistration.windows.net',
        'enrollment.manage.microsoft.com'
    )) {
        $dns = $false
        $https = $false
        try { [void][System.Net.Dns]::GetHostAddresses($endpoint); $dns = $true } catch {}
        try { $https = Test-NetConnection -ComputerName $endpoint -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue } catch {}
        [pscustomobject]@{ Endpoint = $endpoint; DnsResolved = $dns; Tcp443Successful = $https }
    }

    $state = [ordered]@{
        Stage = $Stage
        Generated = (Get-Date).ToString('o')
        ScriptVersion = $ScriptVersion
        Computer = $env:COMPUTERNAME
        User = "$env:USERDOMAIN\$env:USERNAME"
        IsAdministrator = (Test-IsAdministrator)
        JoinState = [ordered]@{
            AzureAdJoined = Get-DsRegValue -Text $dsreg -Name 'AzureAdJoined'
            DomainJoined = Get-DsRegValue -Text $dsreg -Name 'DomainJoined'
            WorkplaceJoined = Get-DsRegValue -Text $dsreg -Name 'WorkplaceJoined'
            AzureAdPrt = Get-DsRegValue -Text $dsreg -Name 'AzureAdPrt'
            DeviceId = Get-DsRegValue -Text $dsreg -Name 'DeviceId'
            TenantId = Get-DsRegValue -Text $dsreg -Name 'TenantId'
        }
        Services = @(Get-Service IntuneManagementExtension, dmwappushservice, DmEnrollmentSvc -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType)
        EnterpriseMgmtTasks = @($taskRows)
        SyncCandidateCount = @(Get-SyncCandidateTasks).Count
        Connectivity = @($endpoints)
    }

    $path = Join-Path $OutputPath "$Stage.json"
    $state | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $path -Encoding UTF8
    Write-Log "Saved $Stage state to $path." 'SUCCESS'
}

function Save-TaskBackups {
    $taskFolder = Join-Path $BackupPath 'EnterpriseMgmtTasks'
    New-Item -ItemType Directory -Path $taskFolder -Force | Out-Null

    foreach ($task in @(Get-EnterpriseMgmtTasks)) {
        try {
            $safeName = ($task.TaskPath.Trim('\') + '_' + $task.TaskName) -replace '[^a-zA-Z0-9._-]', '_'
            Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath |
                Set-Content -LiteralPath (Join-Path $taskFolder "$safeName.xml") -Encoding UTF8
        } catch {
            Write-Log "Could not export task $($task.TaskPath)$($task.TaskName): $($_.Exception.Message)" 'WARN'
        }
    }
}

function Invoke-ArchiveIntuneLogs {
    $logFolder = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs'
    if (-not (Test-Path -LiteralPath $logFolder)) {
        Write-Log 'Intune Management Extension log folder was not found.' 'WARN'
        return
    }

    $destination = Join-Path $BackupPath "IntuneManagementExtension-Logs-$Stamp.zip"
    if ($DryRun) {
        Write-Log "Would archive $logFolder to $destination." 'DRYRUN'
        return
    }

    Compress-Archive -Path (Join-Path $logFolder '*') -DestinationPath $destination -Force
    Write-Log "Archived Intune Management Extension logs to $destination." 'SUCCESS'
}

function Invoke-RestartIntuneManagementExtension {
    Require-Administrator
    $service = Get-Service -Name IntuneManagementExtension -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Log 'Intune Management Extension is not installed on this device.' 'WARN'
        return
    }
    if (-not (Confirm-Action 'Restart the Intune Management Extension service? Active app or script processing may be interrupted.')) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log 'Would restart IntuneManagementExtension.' 'DRYRUN'
        return
    }

    if ($service.Status -eq 'Running') {
        Restart-Service -Name IntuneManagementExtension -Force -ErrorAction Stop
    } else {
        Start-Service -Name IntuneManagementExtension -ErrorAction Stop
    }
    (Get-Service -Name IntuneManagementExtension).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    Write-Log 'Intune Management Extension is running.' 'SUCCESS'
}

function Invoke-RestartMdmServices {
    Require-Administrator
    if (-not (Confirm-Action 'Start or restart available Windows MDM client services?')) { throw 'User cancelled.' }

    foreach ($serviceName in @('dmwappushservice','DmEnrollmentSvc')) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Log "Service $serviceName is not present on this Windows build." 'WARN'
            continue
        }

        if ($DryRun) {
            Write-Log "Would start or restart $serviceName." 'DRYRUN'
            continue
        }

        if ($service.Status -eq 'Running') {
            Restart-Service -Name $serviceName -Force -ErrorAction Stop
        } else {
            Start-Service -Name $serviceName -ErrorAction Stop
        }
        Write-Log "Service $serviceName is running." 'SUCCESS'
    }
}

function Invoke-TriggerMdmSync {
    Require-Administrator
    $tasks = @(Get-SyncCandidateTasks)
    if ($tasks.Count -eq 0) {
        throw 'No enabled EnterpriseMgmt sync candidate tasks were found. The device may not be enrolled.'
    }
    if (-not (Confirm-Action "Start $($tasks.Count) existing EnterpriseMgmt sync task(s)?")) { throw 'User cancelled.' }

    foreach ($task in $tasks) {
        if ($DryRun) {
            Write-Log "Would start task $($task.TaskPath)$($task.TaskName)." 'DRYRUN'
            continue
        }

        Start-ScheduledTask -InputObject $task -ErrorAction Stop
        Write-Log "Started task $($task.TaskPath)$($task.TaskName)." 'SUCCESS'
    }
}

function Invoke-RefreshPrimaryRefreshToken {
    if (-not (Confirm-Action 'Request a Primary Refresh Token refresh for the currently signed-in user?')) { throw 'User cancelled.' }
    if ($DryRun) {
        Write-Log 'Would run dsregcmd.exe /refreshprt for the current user.' 'DRYRUN'
        return
    }

    & dsregcmd.exe /refreshprt 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) {
        throw 'dsregcmd /refreshprt did not complete successfully. Run this action in the affected user session.'
    }
    Write-Log 'Primary Refresh Token refresh was requested for the current user.' 'SUCCESS'
}

function Invoke-FlushDns {
    if (-not (Confirm-Action 'Flush the Windows DNS resolver cache?')) { throw 'User cancelled.' }
    if ($DryRun) {
        Write-Log 'Would flush the DNS resolver cache.' 'DRYRUN'
        return
    }

    if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
        Clear-DnsClientCache
    } else {
        & ipconfig.exe /flushdns | Out-Null
    }
    Write-Log 'DNS resolver cache flushed.' 'SUCCESS'
}

function Invoke-SafeRecoverySet {
    Invoke-ArchiveIntuneLogs
    Invoke-RestartIntuneManagementExtension
    Invoke-RestartMdmServices
    Invoke-FlushDns
    Invoke-TriggerMdmSync
}

Write-Log "Autopilot Safe Recovery Toolkit $ScriptVersion started. DryRun=$DryRun"
Save-State -Stage 'before'
Save-TaskBackups

$hasRepair = $RepairAllSafe -or $RestartIntuneManagementExtension -or $RestartMdmServices -or $TriggerMdmSync -or $RefreshPrimaryRefreshToken -or $FlushDns -or $ArchiveIntuneLogs
if (-not $hasRepair) {
    Write-Log 'Diagnostic-only run completed. No recovery switch was selected.' 'SUCCESS'
    Save-State -Stage 'after'
    exit 0
}

try {
    if ($RepairAllSafe)                     { Invoke-SafeRecoverySet }
    if ($ArchiveIntuneLogs)                 { Invoke-ArchiveIntuneLogs }
    if ($RestartIntuneManagementExtension)  { Invoke-RestartIntuneManagementExtension }
    if ($RestartMdmServices)                { Invoke-RestartMdmServices }
    if ($TriggerMdmSync)                    { Invoke-TriggerMdmSync }
    if ($RefreshPrimaryRefreshToken)        { Invoke-RefreshPrimaryRefreshToken }
    if ($FlushDns)                          { Invoke-FlushDns }
} catch {
    if ($_.Exception.Message -eq 'User cancelled.') {
        $ExitCode = 10
        Write-Log 'Recovery cancelled by the user.' 'WARN'
    } elseif ($_.Exception.Message -match 'elevated') {
        $ExitCode = 4
        Write-Log $_.Exception.Message 'ERROR'
    } elseif ($_.Exception.Message -match 'not found|not enrolled|No enabled') {
        $ExitCode = 2
        Write-Log $_.Exception.Message 'ERROR'
    } else {
        $ExitCode = 20
        Write-Log $_.Exception.Message 'ERROR'
    }
} finally {
    Start-Sleep -Seconds 2
    try { Save-State -Stage 'after' } catch { Write-Log "Post-recovery snapshot failed: $($_.Exception.Message)" 'WARN' }
}

if ($ExitCode -eq 0) {
    Write-Log "Completed successfully. Output: $OutputPath" 'SUCCESS'
} else {
    Write-Log "Completed with exit code $ExitCode. Output: $OutputPath" 'ERROR'
}
exit $ExitCode

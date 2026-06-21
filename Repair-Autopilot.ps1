[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$RestartEnrollmentServices,
    [switch]$RunEnrollmentTasks,
    [switch]$OpenWorkAccountSettings,
    [string]$OutputPath="$env:USERPROFILE\Desktop\AutopilotRepair"
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $OutputPath -Force|Out-Null
$Log=Join-Path $OutputPath ("repair-{0:yyyyMMdd-HHmmss}.log"-f(Get-Date))
function L($m){"$(Get-Date -Format s) $m"|Tee-Object -FilePath $Log -Append}
if(-not($RestartEnrollmentServices-or$RunEnrollmentTasks-or$OpenWorkAccountSettings)){throw'Choose at least one repair action.'}
dsregcmd /status|Out-File (Join-Path $OutputPath 'dsreg-before.txt')
if($RestartEnrollmentServices){
    foreach($s in 'DmEnrollmentSvc','dmwappushservice','Schedule'){
        if(Get-Service $s -ErrorAction SilentlyContinue){
            if($PSCmdlet.ShouldProcess($s,'Restart service')){Restart-Service $s -Force -ErrorAction SilentlyContinue;L "Restarted $s"}
        }
    }
}
if($RunEnrollmentTasks){
    $tasks=Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -ErrorAction SilentlyContinue
    foreach($t in $tasks){if($PSCmdlet.ShouldProcess($t.TaskName,'Start enrollment task')){Start-ScheduledTask -InputObject $t;L "Started $($t.TaskName)"}}
}
if($OpenWorkAccountSettings-and$PSCmdlet.ShouldProcess('Work or school account','Open settings')){Start-Process 'ms-settings:workplace';L'Work account settings opened.'}
Start-Sleep 2
dsregcmd /status|Out-File (Join-Path $OutputPath 'dsreg-after.txt')
L'Repair workflow finished.'

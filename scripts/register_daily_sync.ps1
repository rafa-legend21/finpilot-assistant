$ErrorActionPreference = 'Stop'
$taskName = 'FinPilot Approved GitHub Sync'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $repo 'scripts\push_approved_daily.ps1'

if ((Get-TimeZone).Id -ne 'Eastern Standard Time') {
    throw 'This task must be registered while Windows uses Eastern Time (US & Canada).'
}
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    throw "Scheduled task '$taskName' already exists."
}

$powershell = (Get-Command powershell.exe).Source
$action = New-ScheduledTaskAction -Execute $powershell -Argument (
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
)
$trigger = New-ScheduledTaskTrigger -Daily -At '23:00'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (
    New-TimeSpan -Minutes 10
)
$userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $userName -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal `
    -Description 'Push only explicitly approved FinPilot feature-branch commits at 23:00 Eastern Time.' | Out-Null

Write-Output "Registered '$taskName' for 23:00 Eastern Time."

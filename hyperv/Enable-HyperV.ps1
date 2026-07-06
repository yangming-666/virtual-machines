#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated PowerShell window.'
}

$features = @(
    'Microsoft-Hyper-V-All',
    'Microsoft-Hyper-V-Management-PowerShell'
)

foreach ($feature in $features) {
    Write-Host "Enabling Windows feature: $feature"
    Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
}

Write-Host 'Ensuring the Hyper-V hypervisor starts with Windows.'
bcdedit /set hypervisorlaunchtype auto | Out-Null

if ($Restart) {
    Write-Host 'Restarting now...'
    Restart-Computer
} else {
    Write-Host 'Hyper-V feature enablement is queued. Restart Windows before creating the VM.'
}

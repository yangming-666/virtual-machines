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

Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart | Out-Null
bcdedit /set hypervisorlaunchtype auto | Out-Null

if ($Restart) {
    Restart-Computer
} else {
    Write-Host 'Windows Hypervisor Platform is enabled. Restart Windows before running accelerated QEMU.'
}

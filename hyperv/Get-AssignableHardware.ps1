#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    throw 'The Hyper-V PowerShell module is unavailable. Enable Hyper-V and restart Windows first.'
}

Import-Module Hyper-V

if (-not (Get-Command Get-VMHostAssignableDevice -ErrorAction SilentlyContinue)) {
    throw 'Get-VMHostAssignableDevice is unavailable on this Windows/Hyper-V installation.'
}

Get-VMHostAssignableDevice |
    Select-Object Name, InstancePath, LocationPath |
    Format-List

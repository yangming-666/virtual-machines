#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$CreateVM,
    [switch]$StartVM
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$configPath = Join-Path $scriptRoot 'vm.config.json'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated PowerShell window.'
}

& (Join-Path $scriptRoot 'Export-HostHardware.ps1') -ConfigPath $configPath

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$dataDiskPath = [string]$config.hostHardware.dataDiskPath

if (-not (Test-Path -LiteralPath $dataDiskPath)) {
    & (Join-Path $scriptRoot 'New-HostHardwareDataDisk.ps1') -ConfigPath $configPath
} else {
    Write-Host "Host hardware data disk already exists: $dataDiskPath"
}

if ($CreateVM) {
    & (Join-Path $scriptRoot 'New-ConfiguredVM.ps1') -ConfigPath $configPath
}

if ($StartVM) {
    & (Join-Path $scriptRoot 'Open-VMConsole.ps1') -ConfigPath $configPath -Start
}

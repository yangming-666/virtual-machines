#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$IsoPath,
    [switch]$Start,
    [switch]$PrintOnly
)

$ErrorActionPreference = 'Stop'
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$configPath = Join-Path $scriptRoot 'vm.config.json'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not [string]::IsNullOrWhiteSpace($IsoPath)) {
    & (Join-Path $scriptRoot 'Set-InstallIso.ps1') -ConfigPath $configPath -IsoPath $IsoPath
}

& (Join-Path $scriptRoot 'Install-QEMU.ps1')

if (Test-IsAdministrator) {
    try {
        & (Join-Path $scriptRoot 'Enable-WHPX.ps1')
    } catch {
        Write-Warning $_.Exception.Message
    }
} else {
    Write-Warning 'Not running as Administrator. WHPX enablement is skipped; run Enable-WHPX.ps1 as Administrator and restart for acceleration.'
}

& (Join-Path $scriptRoot 'New-QemuDisk.ps1') -ConfigPath $configPath

if ($PrintOnly) {
    & (Join-Path $scriptRoot 'Start-RealisticVM.ps1') -ConfigPath $configPath -PrintOnly
}

if ($Start) {
    & (Join-Path $scriptRoot 'Start-RealisticVM.ps1') -ConfigPath $configPath
}

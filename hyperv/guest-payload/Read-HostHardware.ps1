#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'host-hardware.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Host hardware manifest not found: $ManifestPath"
}

$hardware = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

Write-Host '=== Host computer ==='
$hardware.computerSystem | Format-List
Write-Host '=== Host BIOS ==='
$hardware.bios | Format-List
Write-Host '=== Host baseboard ==='
$hardware.baseBoard | Format-List
Write-Host '=== Host CPU ==='
$hardware.processor | Format-List
Write-Host '=== Host GPU ==='
$hardware.videoControllers | Format-Table -AutoSize
Write-Host '=== Host physical network adapters ==='
$hardware.networkAdapters | Format-Table -AutoSize
Write-Host '=== Host disks ==='
$hardware.disks | Format-Table -AutoSize

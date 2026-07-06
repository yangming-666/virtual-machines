#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$diskPath = [System.IO.Path]::GetFullPath([string]$config.vm.diskPath)
$basePath = [System.IO.Path]::GetFullPath([string]$config.vm.basePath)
$diskSize = [string]$config.hardware.diskSize

$qemuImg = Get-Command qemu-img.exe -ErrorAction SilentlyContinue
if (-not $qemuImg -and (Test-Path 'C:\Program Files\qemu\qemu-img.exe')) {
    $qemuImgPath = 'C:\Program Files\qemu\qemu-img.exe'
} elseif ($qemuImg) {
    $qemuImgPath = $qemuImg.Source
}
if (-not $qemuImgPath) {
    throw 'qemu-img.exe was not found. Run Install-QEMU.ps1 first.'
}

New-Item -ItemType Directory -Path $basePath -Force | Out-Null

if (Test-Path -LiteralPath $diskPath) {
    if (-not $Force) {
        Write-Host "Disk already exists: $diskPath"
        return
    }
    Remove-Item -LiteralPath $diskPath -Force
}

& $qemuImgPath create -f qcow2 $diskPath $diskSize
Write-Host "Disk created: $diskPath"

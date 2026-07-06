#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$DiskPath,
    [string]$PayloadDirectory
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($PayloadDirectory)) {
    $PayloadDirectory = [string]$config.hostHardware.payloadDirectory
}
if ([string]::IsNullOrWhiteSpace($DiskPath)) {
    $DiskPath = [string]$config.hostHardware.dataDiskPath
}
if ([string]::IsNullOrWhiteSpace($PayloadDirectory) -or [string]::IsNullOrWhiteSpace($DiskPath)) {
    throw 'PayloadDirectory and DiskPath are required.'
}

$PayloadDirectory = [System.IO.Path]::GetFullPath($PayloadDirectory)
$DiskPath = [System.IO.Path]::GetFullPath($DiskPath)

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated PowerShell window.'
}
if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    throw 'The Hyper-V PowerShell module is unavailable. Enable Hyper-V and restart Windows first.'
}
if (-not (Test-Path -LiteralPath $PayloadDirectory)) {
    throw "Payload directory not found: $PayloadDirectory"
}
if (Test-Path -LiteralPath $DiskPath) {
    throw "Data disk already exists: $DiskPath"
}

Import-Module Hyper-V

$diskDirectory = Split-Path -Parent $DiskPath
New-Item -ItemType Directory -Path $diskDirectory -Force | Out-Null

New-VHD -Path $DiskPath -SizeBytes 256MB -Dynamic | Out-Null
$mounted = Mount-VHD -Path $DiskPath -PassThru

try {
    $disk = $mounted | Get-Disk
    Initialize-Disk -Number $disk.Number -PartitionStyle MBR -PassThru | Out-Null
    $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel 'HOSTHW' -Confirm:$false | Out-Null

    $volume = $partition | Get-Volume
    $driveRoot = "$($volume.DriveLetter):\"
    Copy-Item -LiteralPath (Join-Path $PayloadDirectory '*') -Destination $driveRoot -Recurse -Force
    Write-Host "Host hardware data disk created: $DiskPath"
} finally {
    Dismount-VHD -Path $DiskPath
}

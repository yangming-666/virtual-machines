#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Resolve-ScriptPath {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Get-QemuImg {
    $cmd = Get-Command qemu-img.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $knownPath = 'C:\Program Files\qemu\qemu-img.exe'
    if (Test-Path -LiteralPath $knownPath) { return $knownPath }
    throw 'qemu-img.exe was not found. Run Install-QEMU.ps1 first.'
}

function Get-Python {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { return $cmd.Source }
    $cmd = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw 'Python was not found. Install Python or add it to PATH.'
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Resolve-ScriptPath) 'vm.config.json'
}

$scriptRoot = Split-Path -Parent $ConfigPath
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$cacheDirectory = [System.IO.Path]::GetFullPath([string]$config.cloudImage.cacheDirectory)
$seedDirectory = [System.IO.Path]::GetFullPath([string]$config.cloudImage.seedDirectory)
$diskPath = [System.IO.Path]::GetFullPath([string]$config.vm.diskPath)
$diskDirectory = Split-Path -Parent $diskPath
$sshKeyPath = [System.IO.Path]::GetFullPath([string]$config.cloudImage.sshKeyPath)
$preparedMarker = [System.IO.Path]::GetFullPath([string]$config.cloudImage.preparedMarker)

New-Item -ItemType Directory -Path $cacheDirectory, $seedDirectory, $diskDirectory, (Split-Path -Parent $sshKeyPath) -Force | Out-Null

$imageName = Split-Path -Leaf ([string]$config.cloudImage.imageUrl)
$imagePath = Join-Path $cacheDirectory $imageName
$shaPath = Join-Path $cacheDirectory 'SHA256SUMS'

if (-not (Test-Path -LiteralPath $imagePath)) {
    Write-Host "Downloading Ubuntu cloud image: $($config.cloudImage.imageUrl)"
    Invoke-WebRequest -Uri ([string]$config.cloudImage.imageUrl) -OutFile $imagePath
} else {
    Write-Host "Ubuntu cloud image already downloaded: $imagePath"
}

Write-Host "Downloading SHA256SUMS: $($config.cloudImage.sha256Url)"
Invoke-WebRequest -Uri ([string]$config.cloudImage.sha256Url) -OutFile $shaPath

$expectedHash = (Get-Content -LiteralPath $shaPath | Where-Object { $_ -match [regex]::Escape($imageName) } | Select-Object -First 1) -split '\s+' | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($expectedHash)) {
    throw "Could not find $imageName in SHA256SUMS."
}

$actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $imagePath).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
    throw "SHA256 mismatch for $imagePath. Expected $expectedHash, got $actualHash."
}
Write-Host 'Ubuntu cloud image SHA256 verified.'

$qemuImg = Get-QemuImg
$replaceDisk = $Force
if (-not (Test-Path -LiteralPath $diskPath)) {
    $replaceDisk = $true
} elseif ((Get-Item -LiteralPath $diskPath).Length -lt 10MB -and -not (Test-Path -LiteralPath $preparedMarker)) {
    $replaceDisk = $true
}

if ($replaceDisk) {
    if (Test-Path -LiteralPath $diskPath) {
        Remove-Item -LiteralPath $diskPath -Force
    }
    Write-Host "Converting cloud image to VM disk: $diskPath"
    & $qemuImg convert -O qcow2 $imagePath $diskPath
    & $qemuImg resize $diskPath ([string]$config.hardware.diskSize)
    Set-Content -LiteralPath $preparedMarker -Value (Get-Date).ToString('o') -Encoding ASCII
} else {
    Write-Host "VM disk already looks prepared: $diskPath"
}

if (-not (Test-Path -LiteralPath $sshKeyPath)) {
    $sshKeygen = Get-Command ssh-keygen.exe -ErrorAction Stop
    & $sshKeygen.Source -t ed25519 -N '""' -C 'qemu-realistic-codex' -f $sshKeyPath | Out-Null
}
$publicKey = Get-Content -LiteralPath "$sshKeyPath.pub" -Raw

$sshUser = [string]$config.cloudImage.sshUser
$sshPassword = [string]$config.cloudImage.sshPassword

$userData = @"
#cloud-config
hostname: realpc-01
manage_etc_hosts: true
package_update: false
users:
  - default
  - name: $sshUser
    gecos: QEMU Realistic VM User
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: false
    ssh_authorized_keys:
      - $($publicKey.Trim())
ssh_authorized_keys:
  - $($publicKey.Trim())
ssh_pwauth: true
chpasswd:
  expire: false
  users:
    - name: $sshUser
      password: $sshPassword
      type: text
runcmd:
  - [bash, -lc, 'echo cloud-init-ready > /home/$sshUser/cloud-init-ready.txt']
  - [chown, '${sshUser}:${sshUser}', '/home/$sshUser/cloud-init-ready.txt']
final_message: "QEMU realistic Ubuntu VM is ready after `$UPTIME seconds"
"@

$metaData = @"
instance-id: realpc-01-$(Get-Date -Format yyyyMMddHHmmss)
local-hostname: realpc-01
"@

Set-Content -LiteralPath (Join-Path $seedDirectory 'user-data') -Value $userData -Encoding ASCII
Set-Content -LiteralPath (Join-Path $seedDirectory 'meta-data') -Value $metaData -Encoding ASCII

& (Join-Path $scriptRoot 'New-CloudInitIso.ps1') -ConfigPath $ConfigPath

Write-Host "Cloud-init seed written: $seedDirectory"
Write-Host "SSH user: $sshUser"
Write-Host "SSH password: $sshPassword"
Write-Host "SSH private key: $sshKeyPath"

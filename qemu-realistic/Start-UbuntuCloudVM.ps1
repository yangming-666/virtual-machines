#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$UseAcceleration,
    [switch]$Provision,
    [switch]$WaitForSsh
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

$scriptRoot = Split-Path -Parent $ConfigPath
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$basePath = [System.IO.Path]::GetFullPath([string]$config.vm.basePath)
$qemuPidFile = Join-Path $basePath 'qemu.pid'
$seedUrl = "http://10.0.2.2:$([int]$config.cloudImage.httpPort)/"

if ($Provision) {
    & (Join-Path $scriptRoot 'New-CloudInitIso.ps1') -ConfigPath $ConfigPath
    $startArgs.AttachSeedIso = $true
}

$startArgs = @{
    ConfigPath = $ConfigPath
    Headless = $true
    Detached = $true
    PidFile = $qemuPidFile
}
if (-not $UseAcceleration) {
    $startArgs.NoAcceleration = $true
}
& (Join-Path $scriptRoot 'Start-RealisticVM.ps1') @startArgs

if (-not $WaitForSsh) {
    Write-Host "SSH will be available at 127.0.0.1:$([int]$config.network.sshHostPort) when the guest finishes booting."
    return
}

$ssh = Get-Command ssh.exe -ErrorAction Stop
$sshKeyPath = [System.IO.Path]::GetFullPath([string]$config.cloudImage.sshKeyPath)
$sshUser = [string]$config.cloudImage.sshUser
$sshPort = [int]$config.network.sshHostPort
$knownHosts = Join-Path (Split-Path -Parent $sshKeyPath) 'known_hosts'

Write-Host 'Waiting for SSH and cloud-init. This can take several minutes without WHPX acceleration...'
$deadline = (Get-Date).AddMinutes(15)
do {
    Start-Sleep -Seconds 10
    $cmd = @(
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=no',
        '-o', "UserKnownHostsFile=$knownHosts",
        '-i', $sshKeyPath,
        '-p', [string]$sshPort,
        "$sshUser@127.0.0.1",
        'cloud-init status --wait >/dev/null 2>&1; hostname; uname -a; tail -n 5 ~/hardware-realism-firstboot.txt 2>/dev/null || true'
    )
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $ssh.Source @cmd 2>$null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference
    if ($exitCode -eq 0) {
        Write-Host 'VM is reachable over SSH.'
        $output
        return
    }
} while ((Get-Date) -lt $deadline)

throw "Timed out waiting for SSH on 127.0.0.1:$sshPort. The VM may still be booting slowly; check qemu.pid in $basePath."

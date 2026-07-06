#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$StopSeedServer
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$basePath = [System.IO.Path]::GetFullPath([string]$config.vm.basePath)

$qemuPidFile = Join-Path $basePath 'qemu.pid'
if (Test-Path -LiteralPath $qemuPidFile) {
    $processId = [int](Get-Content -LiteralPath $qemuPidFile -Raw)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $processId -Force
        Write-Host "Stopped QEMU PID: $processId"
    }
    Remove-Item -LiteralPath $qemuPidFile -Force
}

if ($StopSeedServer) {
    $httpPidFile = Join-Path $basePath 'cloud-init-http.pid'
    if (Test-Path -LiteralPath $httpPidFile) {
        $processId = [int](Get-Content -LiteralPath $httpPidFile -Raw)
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) {
            Stop-Process -Id $processId -Force
            Write-Host "Stopped cloud-init seed server PID: $processId"
        }
        Remove-Item -LiteralPath $httpPidFile -Force
    }
}

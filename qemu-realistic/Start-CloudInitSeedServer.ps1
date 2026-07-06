#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$seedDirectory = [System.IO.Path]::GetFullPath([string]$config.cloudImage.seedDirectory)
$pidFile = Join-Path ([System.IO.Path]::GetFullPath([string]$config.vm.basePath)) 'cloud-init-http.pid'
$port = [int]$config.cloudImage.httpPort

if (-not (Test-Path -LiteralPath (Join-Path $seedDirectory 'user-data'))) {
    throw "Cloud-init seed is missing. Run Prepare-UbuntuCloudVM.ps1 first: $seedDirectory"
}

if (Test-Path -LiteralPath $pidFile) {
    $oldPid = [int](Get-Content -LiteralPath $pidFile -Raw)
    $oldProcess = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if ($oldProcess) {
        if ($Restart) {
            Stop-Process -Id $oldPid -Force
        } else {
            Write-Host "Cloud-init seed server already running. PID: $oldPid"
            return
        }
    }
}

$python = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $python -or $python.Source -match 'WindowsApps') {
    $python = Get-Command py.exe -ErrorAction Stop
}

$args = @('-m', 'http.server', [string]$port, '--bind', '0.0.0.0', '--directory', $seedDirectory)
$process = Start-Process -FilePath $python.Source -ArgumentList $args -PassThru -WindowStyle Hidden
New-Item -ItemType Directory -Path (Split-Path -Parent $pidFile) -Force | Out-Null
Set-Content -LiteralPath $pidFile -Value $process.Id -Encoding ASCII

Write-Host "Cloud-init seed server started: http://127.0.0.1:$port/"
Write-Host "PID: $($process.Id)"

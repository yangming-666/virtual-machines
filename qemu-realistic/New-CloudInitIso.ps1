#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$seedDirectory = [System.IO.Path]::GetFullPath([string]$config.cloudImage.seedDirectory)
$seedIsoPath = [System.IO.Path]::GetFullPath([string]$config.cloudImage.seedIsoPath)

$userData = Join-Path $seedDirectory 'user-data'
$metaData = Join-Path $seedDirectory 'meta-data'

if (-not (Test-Path -LiteralPath $userData) -or -not (Test-Path -LiteralPath $metaData)) {
    throw "Cloud-init seed files are missing in $seedDirectory. Run Prepare-UbuntuCloudVM.ps1 first."
}

New-Item -ItemType Directory -Path (Split-Path -Parent $seedIsoPath) -Force | Out-Null

$python = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $python -or $python.Source -match 'WindowsApps') {
    $python = Get-Command py.exe -ErrorAction Stop
}

$code = @'
import sys
from pathlib import Path
import pycdlib

user_data = Path(sys.argv[1])
meta_data = Path(sys.argv[2])
iso_path = Path(sys.argv[3])

if iso_path.exists():
    iso_path.unlink()

iso = pycdlib.PyCdlib()
iso.new(interchange_level=3, vol_ident='CIDATA', joliet=True, rock_ridge='1.09')
iso.add_file(str(user_data), iso_path='/USERDATA.;1', joliet_path='/user-data', rr_name='user-data')
iso.add_file(str(meta_data), iso_path='/METADATA.;1', joliet_path='/meta-data', rr_name='meta-data')
iso.write(str(iso_path))
iso.close()
'@

$tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ('new-cidata-{0}.py' -f ([guid]::NewGuid().ToString('N')))
Set-Content -LiteralPath $tempScript -Value $code -Encoding UTF8
try {
    & $python.Source $tempScript $userData $metaData $seedIsoPath
    if ($LASTEXITCODE -ne 0) {
        throw "pycdlib failed to create $seedIsoPath"
    }
} finally {
    Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
}

Write-Host "Cloud-init CIDATA ISO written: $seedIsoPath"

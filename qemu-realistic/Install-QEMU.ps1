#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue) {
    Write-Host 'QEMU is already available on PATH.'
    return
}

$knownPath = 'C:\Program Files\qemu\qemu-system-x86_64.exe'
if (Test-Path -LiteralPath $knownPath) {
    Write-Host "QEMU found: $knownPath"
    return
}

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'winget is not available. Install QEMU manually from https://www.qemu.org/download/#windows and rerun.'
}

winget install --id SoftwareFreedomConservancy.QEMU --exact --accept-package-agreements --accept-source-agreements --disable-interactivity

if (-not (Test-Path -LiteralPath $knownPath) -and -not (Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue)) {
    throw 'QEMU installation finished, but qemu-system-x86_64.exe was not found. Open a new PowerShell window or add QEMU to PATH.'
}

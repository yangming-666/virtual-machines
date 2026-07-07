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

$scriptRoot = Split-Path -Parent $ConfigPath
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

$ssh = Get-Command ssh.exe -ErrorAction Stop
$scp = Get-Command scp.exe -ErrorAction Stop
$sshKeyPath = [System.IO.Path]::GetFullPath([string]$config.cloudImage.sshKeyPath)
$sshUser = [string]$config.cloudImage.sshUser
$sshPort = [int]$config.network.sshHostPort
$knownHosts = Join-Path (Split-Path -Parent $sshKeyPath) 'known_hosts'
$target = "$sshUser@127.0.0.1"

$remoteScript = @'
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y software-properties-common ca-certificates curl wget gnupg
sudo add-apt-repository -y universe
sudo add-apt-repository -y multiverse
sudo apt-get update

sudo apt-get install -y \
  xfce4 \
  xfce4-goodies \
  xrdp \
  dbus-x11 \
  x11-xserver-utils \
  mesa-utils \
  mesa-vulkan-drivers \
  libgl1 \
  libgl1:i386 \
  libglx-mesa0:i386 \
  libgl1-mesa-dri:i386 \
  libvulkan1 \
  libvulkan1:i386 \
  vulkan-tools \
  fonts-noto-cjk \
  steam-installer \
  steam-devices

echo "xfce4-session" > "$HOME/.xsession"
sudo bash -c 'cat >/etc/xrdp/startwm.sh' <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh
sudo adduser xrdp ssl-cert >/dev/null 2>&1 || true
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp

mkdir -p "$HOME/Desktop"
cat > "$HOME/Desktop/Steam.desktop" <<'EOF'
[Desktop Entry]
Name=Steam
Exec=steam
Icon=steam
Terminal=false
Type=Application
Categories=Game;
EOF
chmod +x "$HOME/Desktop/Steam.desktop"

cat > "$HOME/steam-graphical-ready.txt" <<EOF
Steam graphical test environment ready.
Desktop: XFCE via XRDP
Steam command: steam
EOF

echo "steam-graphical-ready"
systemctl --no-pager --full status xrdp | head -n 8
'@

$localTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('setup-steam-graphical-{0}.sh' -f ([guid]::NewGuid().ToString('N')))
Set-Content -LiteralPath $localTemp -Value $remoteScript -Encoding ASCII

try {
    & $scp.Source -o StrictHostKeyChecking=no -o "UserKnownHostsFile=$knownHosts" -i $sshKeyPath -P $sshPort $localTemp "${target}:/tmp/setup-steam-graphical.sh"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to copy setup script into guest.' }

    & $ssh.Source -o StrictHostKeyChecking=no -o "UserKnownHostsFile=$knownHosts" -i $sshKeyPath -p $sshPort $target 'chmod +x /tmp/setup-steam-graphical.sh && /tmp/setup-steam-graphical.sh'
    if ($LASTEXITCODE -ne 0) { throw 'Guest graphical Steam setup failed.' }
} finally {
    Remove-Item -LiteralPath $localTemp -Force -ErrorAction SilentlyContinue
}

Write-Host "Graphical Steam test environment is installed in the guest."
Write-Host "Restart the VM to apply the RDP port forward if it was not already active."
Write-Host "RDP endpoint: 127.0.0.1:$([int]$config.network.rdpHostPort)"

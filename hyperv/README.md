# Hyper-V virtual machine environment

This folder contains a configurable Hyper-V VM setup.

## Files

- `vm.config.json`: VM hardware and boot configuration.
- `Enable-HyperV.ps1`: Enables Hyper-V. Run once as Administrator, then restart Windows.
- `New-ConfiguredVM.ps1`: Creates the VM from the JSON config.
- `Open-VMConsole.ps1`: Opens the Hyper-V console for the configured VM.

## Current default profile

- Name: `DevLab-01`
- CPU: `2` virtual cores
- Memory: `4GB` startup, dynamic `2GB` to `8GB`
- Disk: `60GB` dynamic VHDX
- Network: `Default Switch`
- MAC: `00155D010101`
- Generation: `2`

## Usage

1. Put your OS installer ISO somewhere local, for example:

   ```powershell
   D:\ISO\ubuntu-24.04.2-desktop-amd64.iso
   ```

2. Edit `vm.config.json` and set `boot.isoPath` to that ISO path.

3. Open PowerShell as Administrator and run:

   ```powershell
   Set-Location 'D:\虚拟机\hyperv'
   .\Enable-HyperV.ps1 -Restart
   ```

4. After Windows restarts, open PowerShell as Administrator again and run:

   ```powershell
   Set-Location 'D:\虚拟机\hyperv'
   .\New-ConfiguredVM.ps1
   ```

5. Start and open the VM console:

   ```powershell
   .\Open-VMConsole.ps1 -Start
   ```

## Changing hardware information

Edit `vm.config.json` before creating the VM:

- `hardware.cpuCount`
- `hardware.memoryStartup`
- `hardware.memoryMinimum`
- `hardware.memoryMaximum`
- `hardware.diskSize`
- `network.macAddress`
- `vm.name`
- `vm.basePath`

Hyper-V allows you to set normal virtual hardware sizing and the VM network MAC address. It does not expose arbitrary guest SMBIOS manufacturer/serial spoofing through normal PowerShell VM configuration.

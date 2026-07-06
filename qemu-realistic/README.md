# QEMU realistic hardware profile VM

This setup creates a VM whose guest-visible hardware identity is configured to look like a normal desktop PC:

- SMBIOS BIOS/system/baseboard/chassis fields are set from `vm.config.json`.
- CPU uses QEMU `-cpu max` so WHPX exposes as much host CPU detail as it can.
- Disk is attached through SATA AHCI with a fixed disk serial.
- Network uses an Intel `e1000e` model with a fixed locally chosen MAC address.
- Q35 chipset is used instead of the older i440fx machine type.

It is still a VM. Some low-level PCI, ACPI, timing, display, and hypervisor traits may remain detectable. A consumer Windows host cannot make every virtual device indistinguishable from bare metal without hardware passthrough or running on real hardware.

## Setup

Open PowerShell as Administrator:

```powershell
Set-Location 'D:\虚拟机\qemu-realistic'
.\Enable-WHPX.ps1 -Restart
```

After restart:

```powershell
Set-Location 'D:\虚拟机\qemu-realistic'
.\Setup-FullRealisticVM.ps1 -IsoPath 'D:\ISO\your-installer.iso' -PrintOnly
```

Start the VM:

```powershell
.\Start-RealisticVM.ps1
```

## Automated Ubuntu system

To prepare an installed Ubuntu 24.04 LTS cloud image, inject the default user, and start it headless:

```powershell
.\Prepare-UbuntuCloudVM.ps1
.\Start-UbuntuCloudVM.ps1 -Provision -WaitForSsh
```

Default SSH access after boot:

```powershell
ssh -i 'D:\VMRealPC\ssh\id_ed25519' -p 2222 codex@127.0.0.1
```

Default credentials are `codex` / `codex123`. The SSH key is preferred.

You can also set or change the installer ISO later:

```powershell
.\Set-InstallIso.ps1 -IsoPath 'D:\ISO\your-installer.iso'
```

To inspect the command without booting:

```powershell
.\Start-RealisticVM.ps1 -PrintOnly
```

Inside a Windows guest, copy in and run `Test-GuestHardware.ps1` to inspect the visible hardware profile.

To score the hardware-detection realism from inside a Windows guest:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Assess-GuestHardwareRealism.ps1
```

If you also copy `vm.config.json` into the guest, compare the guest-visible values against the intended profile:

```powershell
.\Assess-GuestHardwareRealism.ps1 -ExpectedConfigPath .\vm.config.json
```

The assessment writes `hardware-realism-report.json` and prints PASS/WARN/FAIL rows. Treat FAIL rows as concrete fingerprints to fix first; WARN rows are realism tradeoffs that may need passthrough or a different virtual device model.

Inside a Linux guest, use:

```sh
sudo dmidecode -t bios -t system -t baseboard -t chassis
lscpu
lsblk -o NAME,MODEL,SERIAL,SIZE
lspci
ip link
```

To score the hardware-detection realism from inside a Linux guest:

```sh
chmod +x ./assess-guest-hardware-realism.sh
./assess-guest-hardware-realism.sh
```

## Changing the hardware identity

Edit these fields before first boot/install:

- `smbios.bios`
- `smbios.system`
- `smbios.baseboard`
- `smbios.chassis`
- `hardware.macAddress`
- `hardware.diskSerial`
- `hardware.cpuCount`
- `hardware.memoryMB`

Keep values internally consistent. For example, do not pair an AMD-only motherboard profile with an Intel CPU profile.

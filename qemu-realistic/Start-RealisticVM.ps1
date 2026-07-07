#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$NoAcceleration,
    [switch]$PrintOnly,
    [switch]$Headless,
    [string]$CloudInitSeedUrl,
    [switch]$AttachSeedIso,
    [switch]$Detached,
    [string]$PidFile
)

$ErrorActionPreference = 'Stop'

function Quote-QemuArg {
    param([string]$Value)
    if ($Value -match '[\s,=]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

function Quote-WindowsArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '\\(?=([\\"]|$))', '\\' -replace '"', '\"') + '"'
}

function Add-SmbiosValue {
    param(
        [System.Collections.Generic.List[string]]$Parts,
        [string]$Name,
        [object]$Value
    )
    if ($null -eq $Value) { return }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $text = $text -replace '\\', '\\' -replace ',', '\,'
    $Parts.Add("$Name=$text")
}

function Find-Qemu {
    $cmd = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $knownPath = 'C:\Program Files\qemu\qemu-system-x86_64.exe'
    if (Test-Path -LiteralPath $knownPath) { return $knownPath }
    throw 'qemu-system-x86_64.exe was not found. Run Install-QEMU.ps1 first.'
}

function Find-UefiCode {
    param([object]$Config)

    $configured = [string]$Config.boot.firmwareCodePath
    if (-not [string]::IsNullOrWhiteSpace($configured) -and (Test-Path -LiteralPath $configured)) {
        return [System.IO.Path]::GetFullPath($configured)
    }

    $candidates = @(
        'C:\Program Files\qemu\share\edk2-x86_64-code.fd',
        'C:\Program Files\qemu\share\edk2-x86_64-code.fd.bak',
        'C:\Program Files\qemu\share\OVMF_CODE.fd',
        'C:\Program Files\qemu\share\edk2\ovmf\OVMF_CODE.fd'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Find-UefiVarsTemplate {
    param([object]$Config)

    $candidates = @(
        'C:\Program Files\qemu\share\edk2-x86_64-vars.fd',
        'C:\Program Files\qemu\share\edk2-i386-vars.fd',
        'C:\Program Files\qemu\share\OVMF_VARS.fd',
        'C:\Program Files\qemu\share\edk2\ovmf\OVMF_VARS.fd'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$qemu = Find-Qemu

$diskPath = [System.IO.Path]::GetFullPath([string]$config.vm.diskPath)
if (-not (Test-Path -LiteralPath $diskPath)) {
    throw "Disk not found: $diskPath. Run New-QemuDisk.ps1 first."
}

$args = [System.Collections.Generic.List[string]]::new()
$args.Add('-name'); $args.Add([string]$config.vm.name)

$machine = [string]$config.hardware.machine
if ([string]::IsNullOrWhiteSpace($machine)) { $machine = 'q35' }
$accelerator = if ($NoAcceleration) { 'tcg' } else { [string]$config.hardware.accelerator }
if ([string]::IsNullOrWhiteSpace($accelerator)) { $accelerator = 'whpx' }
$args.Add('-machine'); $args.Add("$machine,accel=$accelerator")

$args.Add('-smp'); $args.Add([string][int]$config.hardware.cpuCount)
$args.Add('-m'); $args.Add([string][int]$config.hardware.memoryMB)
$args.Add('-cpu'); $args.Add([string]$config.hardware.cpuModel)

$bios = $config.smbios.bios
$biosParts = [System.Collections.Generic.List[string]]::new()
$biosParts.Add('type=0')
Add-SmbiosValue $biosParts 'vendor' $bios.vendor
Add-SmbiosValue $biosParts 'version' $bios.version
Add-SmbiosValue $biosParts 'date' $bios.date
$args.Add('-smbios'); $args.Add(($biosParts -join ','))

$system = $config.smbios.system
$systemParts = [System.Collections.Generic.List[string]]::new()
$systemParts.Add('type=1')
Add-SmbiosValue $systemParts 'manufacturer' $system.manufacturer
Add-SmbiosValue $systemParts 'product' $system.product
Add-SmbiosValue $systemParts 'version' $system.version
if ([string]::IsNullOrWhiteSpace($CloudInitSeedUrl)) {
    Add-SmbiosValue $systemParts 'serial' $system.serial
} else {
    Add-SmbiosValue $systemParts 'serial' "ds=nocloud-net;s=$CloudInitSeedUrl"
}
Add-SmbiosValue $systemParts 'uuid' $system.uuid
Add-SmbiosValue $systemParts 'sku' $system.sku
Add-SmbiosValue $systemParts 'family' $system.family
$args.Add('-smbios'); $args.Add(($systemParts -join ','))

$baseboard = $config.smbios.baseboard
$baseboardParts = [System.Collections.Generic.List[string]]::new()
$baseboardParts.Add('type=2')
Add-SmbiosValue $baseboardParts 'manufacturer' $baseboard.manufacturer
Add-SmbiosValue $baseboardParts 'product' $baseboard.product
Add-SmbiosValue $baseboardParts 'version' $baseboard.version
Add-SmbiosValue $baseboardParts 'serial' $baseboard.serial
Add-SmbiosValue $baseboardParts 'asset' $baseboard.asset
Add-SmbiosValue $baseboardParts 'location' $baseboard.location
$args.Add('-smbios'); $args.Add(($baseboardParts -join ','))

$chassis = $config.smbios.chassis
$chassisParts = [System.Collections.Generic.List[string]]::new()
$chassisParts.Add('type=3')
Add-SmbiosValue $chassisParts 'manufacturer' $chassis.manufacturer
Add-SmbiosValue $chassisParts 'version' $chassis.version
Add-SmbiosValue $chassisParts 'serial' $chassis.serial
Add-SmbiosValue $chassisParts 'asset' $chassis.asset
Add-SmbiosValue $chassisParts 'type' $chassis.type
$args.Add('-smbios'); $args.Add(($chassisParts -join ','))

if ([bool]$config.boot.useUefiIfAvailable) {
    $uefiCode = Find-UefiCode -Config $config
    $uefiVarsTemplate = Find-UefiVarsTemplate -Config $config
    if ($uefiCode -and $uefiVarsTemplate) {
        $varsPath = [System.IO.Path]::GetFullPath([string]$config.boot.firmwareVarsPath)
        if (-not (Test-Path -LiteralPath $varsPath)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $varsPath) -Force | Out-Null
            Copy-Item -LiteralPath $uefiVarsTemplate -Destination $varsPath
        }
        $args.Add('-drive'); $args.Add("if=pflash,format=raw,readonly=on,file=$uefiCode")
        $args.Add('-drive'); $args.Add("if=pflash,format=raw,file=$varsPath")
    } else {
        Write-Warning 'UEFI CODE/VARS firmware files were not found in the QEMU install. Falling back to default BIOS.'
    }
}

$args.Add('-device'); $args.Add('ich9-ahci,id=sata')
$args.Add('-drive'); $args.Add("if=none,id=systemdisk,format=qcow2,file=$diskPath")
$diskDevice = "ide-hd,bus=sata.0,drive=systemdisk,serial=$($config.hardware.diskSerial)"
if ($config.hardware.diskModel) {
    $diskDevice = "$diskDevice,model=$($config.hardware.diskModel)"
}
$args.Add('-device'); $args.Add($diskDevice)

$isoPath = [string]$config.vm.isoPath
if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
    $isoPath = [System.IO.Path]::GetFullPath($isoPath)
    if (-not (Test-Path -LiteralPath $isoPath)) {
        throw "ISO not found: $isoPath"
    }
    $args.Add('-drive'); $args.Add("if=none,id=installcd,media=cdrom,file=$isoPath")
    $installCdDevice = "ide-cd,bus=sata.1,drive=installcd,serial=$($config.hardware.cdromSerial)"
    if ($config.hardware.cdromModel) {
        $installCdDevice = "$installCdDevice,model=$($config.hardware.cdromModel)"
    }
    $args.Add('-device'); $args.Add($installCdDevice)
}

if ($AttachSeedIso -and $config.cloudImage -and $config.cloudImage.seedIsoPath) {
    $seedIsoPath = [System.IO.Path]::GetFullPath([string]$config.cloudImage.seedIsoPath)
    if (Test-Path -LiteralPath $seedIsoPath) {
        $args.Add('-cdrom'); $args.Add($seedIsoPath)
    }
}

$netdev = 'user,id=net0'
if ($config.network -and $config.network.sshHostPort) {
    $netdev = "$netdev,hostfwd=tcp::$([int]$config.network.sshHostPort)-:22"
}
if ($config.network -and $config.network.rdpHostPort) {
    $netdev = "$netdev,hostfwd=tcp::$([int]$config.network.rdpHostPort)-:3389"
}
$args.Add('-netdev'); $args.Add($netdev)
$args.Add('-device'); $args.Add("$($config.hardware.networkModel),netdev=net0,mac=$($config.hardware.macAddress)")
if ($Headless) {
    $args.Add('-display'); $args.Add('none')
    $serialLog = Join-Path ([System.IO.Path]::GetFullPath([string]$config.vm.basePath)) 'serial.log'
    $args.Add('-serial'); $args.Add("file:$serialLog")
} else {
    $args.Add('-vga'); $args.Add([string]$config.display.vga)
}

if ([bool]$config.boot.bootMenu) {
    $args.Add('-boot'); $args.Add('menu=on')
}

if ($PrintOnly) {
    Write-Host $qemu
    Write-Host ($args | ForEach-Object { Quote-QemuArg $_ })
    return
}

if ($Detached) {
    $logDirectory = if ([string]::IsNullOrWhiteSpace($PidFile)) {
        [System.IO.Path]::GetFullPath([string]$config.vm.basePath)
    } else {
        Split-Path -Parent $PidFile
    }
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $stdoutLog = Join-Path $logDirectory 'qemu.stdout.log'
    $stderrLog = Join-Path $logDirectory 'qemu.stderr.log'
    $argumentLine = ($args | ForEach-Object { Quote-WindowsArgument $_ }) -join ' '
    $process = Start-Process -FilePath $qemu -ArgumentList $argumentLine -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog
    if (-not [string]::IsNullOrWhiteSpace($PidFile)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $PidFile) -Force | Out-Null
        Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ASCII
    }
    Write-Host "QEMU started in background. PID: $($process.Id)"
    Write-Host "QEMU stdout: $stdoutLog"
    Write-Host "QEMU stderr: $stderrLog"
    return
}

& $qemu @args

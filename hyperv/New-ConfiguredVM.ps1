#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-ByteCount {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,
        [string]$Name
    )

    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [long]) {
        return [int64]$Value
    }

    $text = ([string]$Value).Trim()
    if ($text -notmatch '^(?<number>\d+(\.\d+)?)\s*(?<unit>B|KB|MB|GB|TB)$') {
        throw "Invalid size for ${Name}: '$Value'. Use values like 4096MB, 4GB, or 60GB."
    }

    $number = [double]$Matches.number
    switch ($Matches.unit.ToUpperInvariant()) {
        'B'  { return [int64]$number }
        'KB' { return [int64]($number * 1KB) }
        'MB' { return [int64]($number * 1MB) }
        'GB' { return [int64]($number * 1GB) }
        'TB' { return [int64]($number * 1TB) }
    }
}

function Assert-MacAddress {
    param([AllowEmptyString()][string]$MacAddress)

    if ([string]::IsNullOrWhiteSpace($MacAddress)) {
        return
    }

    if ($MacAddress -notmatch '^[0-9A-Fa-f]{12}$') {
        throw "Invalid MAC address '$MacAddress'. Use 12 hex digits, for example 00155D010101."
    }
}

function Get-Config {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Resolve-LabPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'vm.basePath is required.'
    }

    return [System.IO.Path]::GetFullPath($Path)
}

$config = Get-Config -Path $ConfigPath

$vmName = [string]$config.vm.name
if ([string]::IsNullOrWhiteSpace($vmName)) {
    throw 'vm.name is required.'
}

$generation = [int]$config.vm.generation
if ($generation -ne 1 -and $generation -ne 2) {
    throw 'vm.generation must be 1 or 2.'
}

$basePath = Resolve-LabPath -Path ([string]$config.vm.basePath)
$vhdDirectory = Join-Path $basePath 'Virtual Hard Disks'
$vhdPath = Join-Path $vhdDirectory "$vmName.vhdx"

$memoryStartup = ConvertTo-ByteCount -Value $config.hardware.memoryStartup -Name 'hardware.memoryStartup'
$memoryMinimum = ConvertTo-ByteCount -Value $config.hardware.memoryMinimum -Name 'hardware.memoryMinimum'
$memoryMaximum = ConvertTo-ByteCount -Value $config.hardware.memoryMaximum -Name 'hardware.memoryMaximum'
$diskSize = ConvertTo-ByteCount -Value $config.hardware.diskSize -Name 'hardware.diskSize'
$cpuCount = [int]$config.hardware.cpuCount

if ($cpuCount -lt 1) {
    throw 'hardware.cpuCount must be at least 1.'
}
if ($memoryMinimum -gt $memoryStartup -or $memoryStartup -gt $memoryMaximum) {
    throw 'Memory must satisfy memoryMinimum <= memoryStartup <= memoryMaximum.'
}

Assert-MacAddress -MacAddress ([string]$config.network.macAddress)

$isoPath = [string]$config.boot.isoPath
if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
    $isoPath = [System.IO.Path]::GetFullPath($isoPath)
    if (-not (Test-Path -LiteralPath $isoPath)) {
        throw "ISO file not found: $isoPath"
    }
}

$hostHardwareDataDiskPath = $null
if ($config.hostHardware -and [bool]$config.hostHardware.attachDataDiskIfPresent) {
    $configuredDataDiskPath = [string]$config.hostHardware.dataDiskPath
    if (-not [string]::IsNullOrWhiteSpace($configuredDataDiskPath)) {
        $hostHardwareDataDiskPath = [System.IO.Path]::GetFullPath($configuredDataDiskPath)
    }
}

Write-Host "Config OK: $vmName, Gen $generation, $cpuCount CPU, $($config.hardware.memoryStartup) RAM, $($config.hardware.diskSize) disk."
if ($ValidateOnly) {
    if ([string]::IsNullOrWhiteSpace($isoPath)) {
        Write-Warning 'boot.isoPath is empty. The VM can be created, but it will not boot an installer until you attach an ISO.'
    }
    if ($hostHardwareDataDiskPath -and -not (Test-Path -LiteralPath $hostHardwareDataDiskPath)) {
        Write-Warning "Host hardware data disk is not present yet: $hostHardwareDataDiskPath"
    }
    return
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated PowerShell window.'
}

if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    throw 'The Hyper-V PowerShell module is unavailable. Run Enable-HyperV.ps1 as Administrator, restart Windows, then try again.'
}

Import-Module Hyper-V

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    throw "A VM named '$vmName' already exists."
}

$switchName = [string]$config.network.switchName
if ([string]::IsNullOrWhiteSpace($switchName)) {
    throw 'network.switchName is required.'
}

$switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
if (-not $switch) {
    if (-not [bool]$config.network.createSwitchIfMissing) {
        throw "Virtual switch '$switchName' was not found. Set createSwitchIfMissing=true or choose an existing switch."
    }

    $switchType = [string]$config.network.switchTypeIfCreated
    if ($switchType -notin @('Internal', 'Private')) {
        throw 'network.switchTypeIfCreated must be Internal or Private for automatic creation.'
    }

    if ($PSCmdlet.ShouldProcess($switchName, "Create $switchType virtual switch")) {
        New-VMSwitch -Name $switchName -SwitchType $switchType | Out-Null
    }
}

if ($PSCmdlet.ShouldProcess($vmName, 'Create Hyper-V virtual machine')) {
    New-Item -ItemType Directory -Path $vhdDirectory -Force | Out-Null

    New-VM `
        -Name $vmName `
        -Generation $generation `
        -MemoryStartupBytes $memoryStartup `
        -Path $basePath `
        -NewVHDPath $vhdPath `
        -NewVHDSizeBytes $diskSize `
        -SwitchName $switchName | Out-Null

    Set-VMProcessor -VMName $vmName -Count $cpuCount
    Set-VMProcessor -VMName $vmName -CompatibilityForMigrationEnabled $false

    if ([bool]$config.hardware.enableNestedVirtualization) {
        Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true
    }

    Set-VMMemory `
        -VMName $vmName `
        -DynamicMemoryEnabled ([bool]$config.hardware.dynamicMemory) `
        -StartupBytes $memoryStartup `
        -MinimumBytes $memoryMinimum `
        -MaximumBytes $memoryMaximum

    if (-not [string]::IsNullOrWhiteSpace($config.network.macAddress)) {
        Set-VMNetworkAdapter -VMName $vmName -StaticMacAddress ([string]$config.network.macAddress)
    }

    if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
        Add-VMDvdDrive -VMName $vmName -Path $isoPath
    }

    if ($hostHardwareDataDiskPath -and (Test-Path -LiteralPath $hostHardwareDataDiskPath)) {
        Add-VMHardDiskDrive -VMName $vmName -Path $hostHardwareDataDiskPath
    }

    if ($generation -eq 2) {
        Set-VMFirmware -VMName $vmName -EnableSecureBoot ([bool]$config.boot.secureBoot)

        if ([bool]$config.boot.secureBoot -and -not [string]::IsNullOrWhiteSpace($config.boot.secureBootTemplate)) {
            Set-VMFirmware -VMName $vmName -SecureBootTemplate ([string]$config.boot.secureBootTemplate)
        }

        $dvd = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dvd) {
            Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($config.vm.notes)) {
        Set-VM -Name $vmName -Notes ([string]$config.vm.notes)
    }

    if (-not [string]::IsNullOrWhiteSpace($config.runtime.checkpointType)) {
        Set-VM -Name $vmName -CheckpointType ([string]$config.runtime.checkpointType)
    }

    Set-VM `
        -Name $vmName `
        -AutomaticStartAction ([string]$config.runtime.automaticStartAction) `
        -AutomaticStopAction ([string]$config.runtime.automaticStopAction)

    Enable-VMIntegrationService -VMName $vmName -Name 'Guest Service Interface' -ErrorAction SilentlyContinue

    Write-Host "VM created: $vmName"

    if ([bool]$config.runtime.startAfterCreate) {
        Start-VM -Name $vmName
    }

    if ([bool]$config.runtime.openConsoleAfterCreate) {
        vmconnect.exe localhost $vmName
    }
}

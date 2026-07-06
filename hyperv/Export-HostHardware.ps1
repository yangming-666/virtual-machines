#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ConfigPath = Join-Path $scriptRoot 'vm.config.json'
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = [string]$config.hostHardware.manifestPath
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    throw 'OutputPath is required. Set hostHardware.manifestPath in vm.config.json or pass -OutputPath.'
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$hardware = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    note = 'This file contains host hardware inventory. Native guest WMI/lspci still reports virtual devices unless a device is physically passed through.'
    computerSystem = Get-CimInstance Win32_ComputerSystem |
        Select-Object Manufacturer, Model, SystemType, TotalPhysicalMemory, HypervisorPresent
    bios = Get-CimInstance Win32_BIOS |
        Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate
    baseBoard = Get-CimInstance Win32_BaseBoard |
        Select-Object Manufacturer, Product, SerialNumber, Version
    processor = Get-CimInstance Win32_Processor |
        Select-Object Name, Manufacturer, ProcessorId, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, VirtualizationFirmwareEnabled, VMMonitorModeExtensions, SecondLevelAddressTranslationExtensions
    memoryModules = Get-CimInstance Win32_PhysicalMemory |
        Select-Object Manufacturer, PartNumber, SerialNumber, Capacity, Speed, ConfiguredClockSpeed, BankLabel, DeviceLocator
    videoControllers = Get-CimInstance Win32_VideoController |
        Select-Object Name, PNPDeviceID, AdapterRAM, DriverVersion, VideoProcessor
    disks = Get-CimInstance Win32_DiskDrive |
        Select-Object Model, SerialNumber, InterfaceType, MediaType, Size, PNPDeviceID
    networkAdapters = Get-CimInstance Win32_NetworkAdapter |
        Where-Object { $_.PhysicalAdapter } |
        Select-Object Name, MACAddress, PNPDeviceID, Speed, AdapterType
    pnpDevices = Get-PnpDevice -PresentOnly |
        Where-Object { $_.Class -in @('Display', 'Net', 'SCSIAdapter', 'System') } |
        Select-Object Class, FriendlyName, InstanceId, Status
}

$hardware | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Host hardware manifest written: $OutputPath"

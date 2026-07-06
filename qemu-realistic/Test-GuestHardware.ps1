# Run this inside a Windows guest to inspect the VM hardware profile.
$ErrorActionPreference = 'Stop'

Write-Host '=== Computer system ==='
Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,SystemType,TotalPhysicalMemory | Format-List

Write-Host '=== BIOS ==='
Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SMBIOSBIOSVersion,SerialNumber,ReleaseDate | Format-List

Write-Host '=== Baseboard ==='
Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer,Product,SerialNumber,Version | Format-List

Write-Host '=== CPU ==='
Get-CimInstance Win32_Processor | Select-Object Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,ProcessorId | Format-List

Write-Host '=== Disk drives ==='
Get-CimInstance Win32_DiskDrive | Select-Object Model,SerialNumber,InterfaceType,Size | Format-Table -AutoSize

Write-Host '=== Network adapters ==='
Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter } | Select-Object Name,MACAddress,AdapterType | Format-Table -AutoSize

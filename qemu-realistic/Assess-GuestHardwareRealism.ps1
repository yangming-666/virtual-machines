# Run this inside a Windows guest.
# It scores how physical-PC-like the guest-visible hardware profile looks.
[CmdletBinding()]
param(
    [string]$ExpectedConfigPath,
    [string]$OutputPath = (Join-Path (Get-Location) 'hardware-realism-report.json'),
    [switch]$JsonOnly
)

$ErrorActionPreference = 'Stop'

$checks = New-Object System.Collections.Generic.List[object]
$totalScore = 0
$maxScore = 0

$virtualPattern = '(?i)(qemu|kvm|bochs|seabios|ovmf|edk2|tianocore|virtualbox|vbox|vmware|parallels|bhyve|xen|hyper-v|hyperv|microsoft virtual|virtual machine|virtio|red hat|rhev|amazon ec2|google compute|openstack)'
$placeholderPattern = '(?i)^(|default string|to be filled by o\.e\.m\.|system product name|system version|sku|none|unknown|not specified|0+|123456789)$'

function Add-Check {
    param(
        [string]$Category,
        [string]$Name,
        [ValidateSet('PASS', 'WARN', 'FAIL')]
        [string]$Status,
        [int]$Score,
        [int]$MaxScore,
        [string]$Evidence,
        [string]$Recommendation = ''
    )

    $script:totalScore += $Score
    $script:maxScore += $MaxScore
    $script:checks.Add([pscustomobject]@{
        category = $Category
        name = $Name
        status = $Status
        score = $Score
        maxScore = $MaxScore
        evidence = $Evidence
        recommendation = $Recommendation
    }) | Out-Null
}

function Join-Values {
    param([object[]]$Values)
    return (($Values | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ }) -join ' | ')
}

function Test-HasVirtualKeyword {
    param([object[]]$Values)
    return ((Join-Values $Values) -match $virtualPattern)
}

function Test-IsPlaceholder {
    param([object]$Value)
    if ($null -eq $Value) { return $true }
    return ([string]$Value).Trim() -match $placeholderPattern
}

function Get-ExpectedConfig {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Expected config not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$expected = Get-ExpectedConfig -Path $ExpectedConfigPath

$computer = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$baseBoard = Get-CimInstance Win32_BaseBoard
$chassis = Get-CimInstance Win32_SystemEnclosure
$cpu = Get-CimInstance Win32_Processor
$disks = @(Get-CimInstance Win32_DiskDrive)
$nics = @(Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter })
$videos = @(Get-CimInstance Win32_VideoController)
$pnp = @(Get-CimInstance Win32_PnPEntity)
$services = @(Get-CimInstance Win32_Service)

$dmiValues = @(
    $computer.Manufacturer, $computer.Model, $computer.SystemFamily, $computer.SystemSKUNumber,
    $bios.Manufacturer, $bios.SMBIOSBIOSVersion, $bios.SerialNumber,
    $baseBoard.Manufacturer, $baseBoard.Product, $baseBoard.SerialNumber, $baseBoard.Version,
    $chassis.Manufacturer, $chassis.SerialNumber, $chassis.SMBIOSAssetTag
)

if (Test-HasVirtualKeyword $dmiValues) {
    Add-Check 'SMBIOS' 'No virtualization keywords in DMI' 'FAIL' 0 16 (Join-Values $dmiValues) 'Adjust -smbios values; avoid QEMU/Virtual/Bochs/OVMF/EDK2 strings.'
} else {
    Add-Check 'SMBIOS' 'No virtualization keywords in DMI' 'PASS' 16 16 (Join-Values $dmiValues)
}

$coreDmi = @(
    $bios.Manufacturer, $bios.SMBIOSBIOSVersion,
    $computer.Manufacturer, $computer.Model,
    $baseBoard.Manufacturer, $baseBoard.Product
)
if (($coreDmi | Where-Object { Test-IsPlaceholder $_ }).Count -gt 0) {
    Add-Check 'SMBIOS' 'Core DMI fields are specific' 'WARN' 6 12 (Join-Values $coreDmi) 'Use real-looking vendor, model, BIOS version, and baseboard product values.'
} else {
    Add-Check 'SMBIOS' 'Core DMI fields are specific' 'PASS' 12 12 (Join-Values $coreDmi)
}

$identityValues = @($bios.SerialNumber, $baseBoard.SerialNumber, $chassis.SerialNumber)
if (($identityValues | Where-Object { Test-IsPlaceholder $_ }).Count -gt 0) {
    Add-Check 'SMBIOS' 'Serial numbers are populated' 'WARN' 4 8 (Join-Values $identityValues) 'Use non-default serial values for BIOS/baseboard/chassis.'
} else {
    Add-Check 'SMBIOS' 'Serial numbers are populated' 'PASS' 8 8 (Join-Values $identityValues)
}

$cpuValues = @($cpu.Name, $cpu.Manufacturer, $cpu.Description)
if (Test-HasVirtualKeyword $cpuValues) {
    Add-Check 'CPU' 'CPU name does not expose VM model' 'FAIL' 0 10 (Join-Values $cpuValues) 'Use a host/max CPU model that exposes a normal CPU name.'
} else {
    Add-Check 'CPU' 'CPU name does not expose VM model' 'PASS' 10 10 (Join-Values $cpuValues)
}

$logicalProcessors = ($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
if ($logicalProcessors -ge 2 -and $logicalProcessors -le 32) {
    Add-Check 'CPU' 'CPU topology is plausible' 'PASS' 5 5 "$logicalProcessors logical processors"
} else {
    Add-Check 'CPU' 'CPU topology is plausible' 'WARN' 2 5 "$logicalProcessors logical processors" 'Use a normal desktop CPU count such as 4, 6, 8, 12, or 16.'
}

if ($computer.PSObject.Properties.Name -contains 'HypervisorPresent' -and $computer.HypervisorPresent) {
    Add-Check 'CPU' 'Windows hypervisor-present flag' 'WARN' 0 5 'HypervisorPresent=True' 'Some detection tools treat this as a virtualization signal.'
} else {
    Add-Check 'CPU' 'Windows hypervisor-present flag' 'PASS' 5 5 'HypervisorPresent is false or unavailable'
}

$diskValues = @($disks | ForEach-Object { Join-Values @($_.Model, $_.SerialNumber, $_.PNPDeviceID, $_.InterfaceType) })
if ($disks.Count -eq 0) {
    Add-Check 'Storage' 'At least one disk is visible' 'FAIL' 0 4 'No Win32_DiskDrive entries'
} else {
    Add-Check 'Storage' 'At least one disk is visible' 'PASS' 4 4 "$($disks.Count) disk(s)"
}

if (Test-HasVirtualKeyword $diskValues) {
    Add-Check 'Storage' 'Disk identity avoids VM keywords' 'FAIL' 0 8 (Join-Values $diskValues) 'Avoid disk models or PNP IDs that include QEMU/VirtIO/Virtual.'
} else {
    Add-Check 'Storage' 'Disk identity avoids VM keywords' 'PASS' 8 8 (Join-Values $diskValues)
}

$diskSerials = @($disks | ForEach-Object { $_.SerialNumber })
if (($diskSerials | Where-Object { -not (Test-IsPlaceholder $_) }).Count -gt 0) {
    Add-Check 'Storage' 'Disk serial number exists' 'PASS' 5 5 (Join-Values $diskSerials)
} else {
    Add-Check 'Storage' 'Disk serial number exists' 'FAIL' 0 5 (Join-Values $diskSerials) 'Set a stable serial on the disk device.'
}

$nicValues = @($nics | ForEach-Object { Join-Values @($_.Name, $_.Manufacturer, $_.AdapterType, $_.PNPDeviceID, $_.MACAddress) })
if ($nics.Count -eq 0) {
    Add-Check 'Network' 'Physical network adapter is visible' 'FAIL' 0 4 'No physical adapters'
} else {
    Add-Check 'Network' 'Physical network adapter is visible' 'PASS' 4 4 "$($nics.Count) adapter(s)"
}

if (Test-HasVirtualKeyword $nicValues) {
    Add-Check 'Network' 'Network adapter avoids VM keywords' 'FAIL' 0 8 (Join-Values $nicValues) 'Use e1000e or passed-through hardware instead of virtio/qemu virtual NIC names.'
} else {
    Add-Check 'Network' 'Network adapter avoids VM keywords' 'PASS' 8 8 (Join-Values $nicValues)
}

$knownVmMacPrefixes = '^(52:54:00|08:00:27|00:05:69|00:0C:29|00:1C:14|00:50:56)'
$macs = @($nics | ForEach-Object { $_.MACAddress } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if (($macs | Where-Object { $_ -match $knownVmMacPrefixes }).Count -gt 0) {
    Add-Check 'Network' 'MAC prefix is not a common VM OUI' 'FAIL' 0 5 (Join-Values $macs) 'Use a non-conflicting, realistic MAC prefix.'
} elseif ($macs.Count -gt 0) {
    Add-Check 'Network' 'MAC prefix is not a common VM OUI' 'PASS' 5 5 (Join-Values $macs)
} else {
    Add-Check 'Network' 'MAC prefix is not a common VM OUI' 'WARN' 2 5 'No MAC address found'
}

$videoValues = @($videos | ForEach-Object { Join-Values @($_.Name, $_.AdapterCompatibility, $_.PNPDeviceID, $_.VideoProcessor) })
if (Test-HasVirtualKeyword $videoValues) {
    Add-Check 'Display' 'Display adapter avoids VM keywords' 'FAIL' 0 8 (Join-Values $videoValues) 'Use GPU passthrough for the strongest display realism; otherwise this may remain detectable.'
} elseif (($videoValues -join ' ') -match '(?i)(basic display|standard vga)') {
    Add-Check 'Display' 'Display adapter avoids generic fallback names' 'WARN' 3 8 (Join-Values $videoValues) 'Install a suitable driver or use passthrough for stronger display realism.'
} else {
    Add-Check 'Display' 'Display adapter identity is plausible' 'PASS' 8 8 (Join-Values $videoValues)
}

$pnpValues = @($pnp | ForEach-Object { Join-Values @($_.Name, $_.Manufacturer, $_.DeviceID, $_.PNPDeviceID) })
$virtualPnpHits = @($pnpValues | Where-Object { $_ -match $virtualPattern } | Select-Object -First 12)
if ($virtualPnpHits.Count -gt 0) {
    Add-Check 'PCI/PNP' 'No obvious virtual devices in PNP tree' 'FAIL' 0 12 (Join-Values $virtualPnpHits) 'Replace virtio/qemu devices or use passthrough where practical.'
} else {
    Add-Check 'PCI/PNP' 'No obvious virtual devices in PNP tree' 'PASS' 12 12 'No obvious virtual keywords found in sampled PNP devices'
}

$serviceHits = @($services | Where-Object { ($_.Name + ' ' + $_.DisplayName + ' ' + $_.PathName) -match $virtualPattern } | Select-Object -First 12 Name, DisplayName, State)
if ($serviceHits.Count -gt 0) {
    Add-Check 'Drivers/Services' 'No obvious VM guest services' 'WARN' 2 6 (($serviceHits | ForEach-Object { "$($_.Name)/$($_.DisplayName)" }) -join ' | ') 'Guest tools and virtio agents are useful, but they reduce hardware-detection realism.'
} else {
    Add-Check 'Drivers/Services' 'No obvious VM guest services' 'PASS' 6 6 'No obvious VM service names found'
}

if ($expected) {
    $expectedChecks = @(
        @{ name = 'System manufacturer'; actual = $computer.Manufacturer; expected = $expected.smbios.system.manufacturer },
        @{ name = 'System product'; actual = $computer.Model; expected = $expected.smbios.system.product },
        @{ name = 'BIOS vendor'; actual = $bios.Manufacturer; expected = $expected.smbios.bios.vendor },
        @{ name = 'Baseboard product'; actual = $baseBoard.Product; expected = $expected.smbios.baseboard.product },
        @{ name = 'Configured disk serial'; actual = (Join-Values $diskSerials); expected = $expected.hardware.diskSerial },
        @{ name = 'Configured MAC'; actual = (Join-Values $macs); expected = $expected.hardware.macAddress }
    )

    $matched = 0
    foreach ($item in $expectedChecks) {
        if (-not [string]::IsNullOrWhiteSpace([string]$item.expected) -and ([string]$item.actual -like "*$($item.expected)*")) {
            $matched++
        }
    }

    $score = [int][Math]::Round(10 * ($matched / [double]$expectedChecks.Count))
    $status = if ($score -ge 8) { 'PASS' } elseif ($score -ge 5) { 'WARN' } else { 'FAIL' }
    Add-Check 'Config match' 'Guest values match vm.config.json' $status $score 10 "$matched/$($expectedChecks.Count) expected values matched" 'If this fails, check QEMU startup arguments and whether the guest was booted with this config.'
}

$percent = if ($maxScore -gt 0) { [Math]::Round(($totalScore / [double]$maxScore) * 100, 1) } else { 0 }
$rating = if ($percent -ge 90) {
    'Strong'
} elseif ($percent -ge 75) {
    'Good'
} elseif ($percent -ge 55) {
    'Mixed'
} else {
    'Weak'
}

$report = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('o')
    score = $totalScore
    maxScore = $maxScore
    percent = $percent
    rating = $rating
    summary = 'This measures guest-visible hardware realism. It cannot prove that a VM is indistinguishable from bare metal.'
    checks = $checks
    inventory = [pscustomobject]@{
        computerSystem = $computer | Select-Object Manufacturer, Model, SystemFamily, SystemSKUNumber, HypervisorPresent
        bios = $bios | Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber, ReleaseDate
        baseBoard = $baseBoard | Select-Object Manufacturer, Product, SerialNumber, Version
        chassis = $chassis | Select-Object Manufacturer, SerialNumber, SMBIOSAssetTag, ChassisTypes
        processor = $cpu | Select-Object Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, ProcessorId
        disks = $disks | Select-Object Model, SerialNumber, InterfaceType, PNPDeviceID, Size
        networkAdapters = $nics | Select-Object Name, Manufacturer, MACAddress, AdapterType, PNPDeviceID
        videoControllers = $videos | Select-Object Name, AdapterCompatibility, VideoProcessor, PNPDeviceID
    }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

if ($JsonOnly) {
    $report | ConvertTo-Json -Depth 8
    return
}

Write-Host "Hardware realism score: $totalScore / $maxScore ($percent%) - $rating"
Write-Host "Report written: $OutputPath"
Write-Host ''
$checks |
    Sort-Object @{ Expression = { if ($_.status -eq 'FAIL') { 0 } elseif ($_.status -eq 'WARN') { 1 } else { 2 } } }, Category, Name |
    Format-Table Status, Category, Name, Score, MaxScore, Evidence -AutoSize

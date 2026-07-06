#!/usr/bin/env sh
# Run this inside a Linux guest. It scores guest-visible hardware realism.
set -eu

score=0
max=0
failures=""
warnings=""

virtual_re='qemu|kvm|bochs|seabios|ovmf|edk2|tianocore|virtualbox|vbox|vmware|parallels|bhyve|xen|hyper-v|hyperv|microsoft virtual|virtual machine|virtio|red hat|rhev|amazon ec2|google compute|openstack'
placeholder_re='^(|default string|to be filled by o\.e\.m\.|system product name|system version|sku|none|unknown|not specified|0+|123456789)$'

add_check() {
  status="$1"
  points="$2"
  possible="$3"
  name="$4"
  evidence="$5"
  score=$((score + points))
  max=$((max + possible))
  printf '%-5s %2s/%-2s %s -- %s\n' "$status" "$points" "$possible" "$name" "$evidence"
  case "$status" in
    FAIL) failures="${failures}
- ${name}: ${evidence}" ;;
    WARN) warnings="${warnings}
- ${name}: ${evidence}" ;;
  esac
}

read_file() {
  path="$1"
  if [ -r "$path" ]; then
    tr -d '\000' < "$path" | head -n 1
  else
    printf ''
  fi
}

contains_virtual() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -E "$virtual_re" >/dev/null 2>&1
}

is_placeholder() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -E "$placeholder_re" >/dev/null 2>&1
}

sysfs_dmi="/sys/class/dmi/id"
bios_vendor="$(read_file "$sysfs_dmi/bios_vendor")"
bios_version="$(read_file "$sysfs_dmi/bios_version")"
sys_vendor="$(read_file "$sysfs_dmi/sys_vendor")"
product_name="$(read_file "$sysfs_dmi/product_name")"
product_serial="$(read_file "$sysfs_dmi/product_serial")"
board_vendor="$(read_file "$sysfs_dmi/board_vendor")"
board_name="$(read_file "$sysfs_dmi/board_name")"
board_serial="$(read_file "$sysfs_dmi/board_serial")"
chassis_vendor="$(read_file "$sysfs_dmi/chassis_vendor")"
chassis_serial="$(read_file "$sysfs_dmi/chassis_serial")"
dmi_values="$bios_vendor $bios_version $sys_vendor $product_name $product_serial $board_vendor $board_name $board_serial $chassis_vendor $chassis_serial"

echo "Hardware realism assessment"
echo "==========================="

if contains_virtual "$dmi_values"; then
  add_check FAIL 0 18 "DMI has no virtualization keywords" "$dmi_values"
else
  add_check PASS 18 18 "DMI has no virtualization keywords" "$dmi_values"
fi

placeholder_count=0
for value in "$bios_vendor" "$bios_version" "$sys_vendor" "$product_name" "$board_vendor" "$board_name"; do
  if is_placeholder "$value"; then
    placeholder_count=$((placeholder_count + 1))
  fi
done
if [ "$placeholder_count" -gt 0 ]; then
  add_check WARN 6 12 "Core DMI fields are specific" "$placeholder_count placeholder value(s)"
else
  add_check PASS 12 12 "Core DMI fields are specific" "$sys_vendor / $product_name / $board_name"
fi

serial_count=0
for value in "$product_serial" "$board_serial" "$chassis_serial"; do
  if ! is_placeholder "$value"; then
    serial_count=$((serial_count + 1))
  fi
done
if [ "$serial_count" -ge 2 ]; then
  add_check PASS 8 8 "Serial numbers are populated" "$serial_count serial(s)"
else
  add_check WARN 3 8 "Serial numbers are populated" "$serial_count serial(s)"
fi

cpu_info="$(cat /proc/cpuinfo 2>/dev/null || true)"
cpu_model="$(printf '%s\n' "$cpu_info" | awk -F: '/model name/ {gsub(/^ /,"",$2); print $2; exit}')"
cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '0')"
if contains_virtual "$cpu_model"; then
  add_check FAIL 0 10 "CPU name avoids VM model" "$cpu_model"
else
  add_check PASS 10 10 "CPU name avoids VM model" "$cpu_model"
fi
if [ "$cpu_count" -ge 2 ] 2>/dev/null && [ "$cpu_count" -le 32 ] 2>/dev/null; then
  add_check PASS 5 5 "CPU topology is plausible" "$cpu_count logical CPU(s)"
else
  add_check WARN 2 5 "CPU topology is plausible" "$cpu_count logical CPU(s)"
fi
if grep -qi hypervisor /proc/cpuinfo 2>/dev/null; then
  add_check WARN 0 5 "CPU hypervisor flag is hidden" "hypervisor flag present"
else
  add_check PASS 5 5 "CPU hypervisor flag is hidden" "hypervisor flag absent"
fi

disk_info=""
if command -v lsblk >/dev/null 2>&1; then
  disk_info="$(lsblk -dn -o NAME,MODEL,SERIAL,TRAN,SIZE 2>/dev/null || true)"
fi
if [ -z "$disk_info" ]; then
  add_check WARN 2 6 "Disk inventory is readable" "lsblk unavailable or no disks"
elif contains_virtual "$disk_info"; then
  add_check FAIL 0 12 "Disk identity avoids VM keywords" "$disk_info"
else
  add_check PASS 12 12 "Disk identity avoids VM keywords" "$disk_info"
fi
if printf '%s' "$disk_info" | awk '{print $3}' | grep -E '[A-Za-z0-9]{6,}' >/dev/null 2>&1; then
  add_check PASS 5 5 "Disk serial number exists" "$disk_info"
else
  add_check WARN 2 5 "Disk serial number exists" "$disk_info"
fi

pci_info=""
if command -v lspci >/dev/null 2>&1; then
  pci_info="$(lspci 2>/dev/null || true)"
fi
if [ -z "$pci_info" ]; then
  add_check WARN 2 8 "PCI inventory is readable" "lspci unavailable"
elif contains_virtual "$pci_info"; then
  add_check FAIL 0 14 "PCI devices avoid VM keywords" "$(printf '%s\n' "$pci_info" | grep -Ei "$virtual_re" | head -n 8)"
else
  add_check PASS 14 14 "PCI devices avoid VM keywords" "No obvious VM keywords in lspci"
fi

net_info=""
if command -v ip >/dev/null 2>&1; then
  net_info="$(ip -o link 2>/dev/null | awk -F'link/ether ' '/link\/ether/ {print $2}' | awk '{print $1}')"
fi
if printf '%s\n' "$net_info" | grep -Ei '^(52:54:00|08:00:27|00:05:69|00:0c:29|00:1c:14|00:50:56)' >/dev/null 2>&1; then
  add_check FAIL 0 6 "MAC prefix is not a common VM OUI" "$net_info"
elif [ -n "$net_info" ]; then
  add_check PASS 6 6 "MAC prefix is not a common VM OUI" "$net_info"
else
  add_check WARN 2 6 "MAC prefix is not a common VM OUI" "No MAC found"
fi

percent=0
if [ "$max" -gt 0 ]; then
  percent=$((score * 100 / max))
fi
if [ "$percent" -ge 90 ]; then
  rating="Strong"
elif [ "$percent" -ge 75 ]; then
  rating="Good"
elif [ "$percent" -ge 55 ]; then
  rating="Mixed"
else
  rating="Weak"
fi

echo
echo "Score: $score / $max (${percent}%) - $rating"
echo "This measures guest-visible hardware realism; it cannot prove bare-metal indistinguishability."

if [ -n "$failures" ]; then
  echo
  echo "Failures:$failures"
fi
if [ -n "$warnings" ]; then
  echo
  echo "Warnings:$warnings"
fi

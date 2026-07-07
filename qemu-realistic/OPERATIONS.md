# QEMU Realistic Steam Test VM 操作文档

本文档记录当前项目方案的日常操作、Steam 图形环境使用方式，以及硬件真实性检测流程。

## 1. 当前环境概览

- 宿主机工作目录：`D:\虚拟机`
- QEMU 配置目录：`D:\虚拟机\qemu-realistic`
- VM 运行目录：`D:\VMRealPC`
- 系统盘：`D:\VMRealPC\RealPC-01.qcow2`
- Guest 系统：Ubuntu 24.04 LTS
- SSH 端口：`127.0.0.1:2222`
- RDP 端口：`127.0.0.1:3390`
- 用户名：`codex`
- 密码：`codex123`
- SSH 私钥：`D:\VMRealPC\ssh\id_ed25519`

当前硬件画像检测结果：

```text
Score: 95 / 95 (100%) - Strong
```

## 2. 启动虚拟机

在宿主机 PowerShell 中执行：

```powershell
Set-Location 'D:\虚拟机'
.\qemu-realistic\Start-UbuntuCloudVM.ps1 -WaitForSsh
```

看到类似输出即代表 VM 已启动并可 SSH：

```text
VM is reachable over SSH.
realpc-01
Linux realpc-01 ...
```

## 3. SSH 登录

```powershell
ssh -i 'D:\VMRealPC\ssh\id_ed25519' -p 2222 codex@127.0.0.1
```

## 4. 图形桌面与 Steam

使用 Windows 远程桌面连接：

```powershell
mstsc /v:127.0.0.1:3390
```

登录信息：

```text
用户名：codex
密码：codex123
```

进入 XFCE 桌面后，可通过桌面快捷方式启动 Steam，或打开终端执行：

```bash
steam
```

首次启动 Steam 会下载并更新运行时组件，等待完成后再登录账号。

## 5. 硬件真实性检测流程

### 5.1 一键检测

在宿主机 PowerShell 中执行：

```powershell
$ssh = 'C:\Windows\System32\OpenSSH\ssh.exe'
$key = 'D:\VMRealPC\ssh\id_ed25519'
$known = 'D:\VMRealPC\ssh\known_hosts'
& $ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=$known" -i $key -p 2222 codex@127.0.0.1 '~/assess-guest-hardware-realism.sh'
```

理想输出：

```text
Hardware realism assessment
===========================
PASS ... DMI has no virtualization keywords
PASS ... CPU name avoids VM model
PASS ... CPU hypervisor flag is hidden
PASS ... Disk identity avoids VM keywords
PASS ... PCI devices avoid VM keywords

Score: 95 / 95 (100%) - Strong
```

### 5.2 检测项说明

检测脚本会检查以下项目：

- SMBIOS/DMI 是否包含 `QEMU`、`Virtual`、`Bochs`、`KVM` 等关键词
- BIOS、整机、主板字段是否具体
- BIOS、主板、机箱序列号是否存在
- CPU 名称是否暴露虚拟化模型
- `/proc/cpuinfo` 是否存在 `hypervisor` flag
- 磁盘 model/serial 是否暴露虚拟化关键词
- PCI 设备列表是否有明显虚拟化关键词
- MAC 地址是否属于常见虚拟机 OUI

### 5.3 Guest 内手动检测

SSH 登录后可执行：

```bash
~/assess-guest-hardware-realism.sh
```

也可以单独查看常见硬件信息：

```bash
sudo dmidecode -t bios -t system -t baseboard -t chassis
lscpu
lsblk -dn -o NAME,MODEL,SERIAL,TRAN,SIZE
lspci
ip link
grep -i hypervisor /proc/cpuinfo || echo "hypervisor flag absent"
```

## 6. Steam 图形环境检测流程

### 6.1 检查 XRDP 和 Steam

在宿主机 PowerShell 中执行：

```powershell
$ssh = 'C:\Windows\System32\OpenSSH\ssh.exe'
$key = 'D:\VMRealPC\ssh\id_ed25519'
$known = 'D:\VMRealPC\ssh\known_hosts'
& $ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=$known" -i $key -p 2222 codex@127.0.0.1 'systemctl is-active xrdp; systemctl is-active xrdp-sesman; command -v steam; dpkg -l steam-installer steam-devices xrdp xfce4 | grep "^ii"'
```

预期包含：

```text
active
active
/usr/games/steam
ii  steam-installer
ii  steam-devices
ii  xrdp
ii  xfce4
```

### 6.2 检查宿主机端口转发

```powershell
Get-NetTCPConnection -LocalPort 2222,3390 -ErrorAction SilentlyContinue |
  Select-Object LocalAddress,LocalPort,State,OwningProcess
```

预期：

```text
0.0.0.0  2222  Listen
0.0.0.0  3390  Listen
```

### 6.3 图形能力快速检查

SSH 登录后执行：

```bash
glxinfo -B
vulkaninfo --summary
```

说明：

- 当前环境适合 Steam 客户端和轻量图形测试。
- 没有 GPU 直通时，3D 游戏性能会较弱。
- 如果 `glxinfo -B` 在 SSH 中没有输出，可在 RDP 桌面终端中执行。

## 7. 重启虚拟机

推荐在 guest 内正常关机：

```bash
sudo poweroff
```

然后在宿主机重新启动：

```powershell
Set-Location 'D:\虚拟机'
.\qemu-realistic\Start-UbuntuCloudVM.ps1 -WaitForSsh
```

如果需要强制停止：

```powershell
Stop-Process -Name qemu-system-x86_64 -Force
```

## 8. 重新安装或重建系统盘

仅在需要重置系统时执行。此操作会覆盖当前 VM 系统盘。

```powershell
Set-Location 'D:\虚拟机'
.\qemu-realistic\Prepare-UbuntuCloudVM.ps1 -Force
.\qemu-realistic\Start-UbuntuCloudVM.ps1 -Provision -WaitForSsh
.\qemu-realistic\Setup-SteamGraphicalGuest.ps1
```

## 9. 配置文件位置

主要配置文件：

```text
D:\虚拟机\qemu-realistic\vm.config.json
```

常用字段：

- `hardware.cpuCount`
- `hardware.memoryMB`
- `hardware.cpuModel`
- `hardware.diskModel`
- `hardware.diskSerial`
- `hardware.macAddress`
- `smbios.bios`
- `smbios.system`
- `smbios.baseboard`
- `network.sshHostPort`
- `network.rdpHostPort`

修改配置后需要重启 VM 才会生效。

## 10. 常见问题

### RDP 连不上

检查 VM 是否运行：

```powershell
Get-Process qemu-system-x86_64
```

检查端口：

```powershell
Get-NetTCPConnection -LocalPort 3390 -ErrorAction SilentlyContinue
```

检查 guest 内服务：

```powershell
ssh -i 'D:\VMRealPC\ssh\id_ed25519' -p 2222 codex@127.0.0.1 'systemctl status xrdp --no-pager; systemctl status xrdp-sesman --no-pager'
```

### SSH 提示 host key changed

重建系统盘后清理 known hosts：

```powershell
Remove-Item 'D:\VMRealPC\ssh\known_hosts' -Force -ErrorAction SilentlyContinue
```

### Steam 首次启动很慢

首次启动会下载 Steam runtime 和客户端更新。保持 RDP 会话打开等待完成。

### 硬件检测分数下降

先确认 VM 是用当前配置启动：

```powershell
.\qemu-realistic\Start-RealisticVM.ps1 -NoAcceleration -Headless -PrintOnly
```

关键参数应包含：

```text
-cpu EPYC-v3,hypervisor=off
model=WDC WD10EZEX-08WN4A0
mac=50:7B:9D:35:42:18
```

## 11. 注意事项

本环境用于合法的兼容性与图形客户端测试。当前硬件真实性检测只说明 guest 内常见硬件字段较真实，不能证明该 VM 对所有平台、游戏或反作弊系统不可识别。

重度 3D 游戏需要 GPU 直通或更强图形虚拟化方案；当前环境更适合 Steam 客户端、轻量图形程序和硬件画像测试。

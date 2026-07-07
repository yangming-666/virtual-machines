# 本地运行产物清单

本文档列出当前项目中没有进入 git、但和虚拟机运行相关的本地文件。克隆仓库后，不建议把这些大文件、密钥或运行日志直接提交到 git；按本文档重新生成即可。

## 1. 被 `.gitignore` 排除的仓库内文件

当前仓库 `.gitignore` 会排除镜像、虚拟磁盘、缓存目录和临时目录：

```text
*.img
*.iso
*.vhdx
*.vhd
*.qcow2
*.qcow
*.vdi
*.vmdk
**/cache/
**/tmp/
```

当前本机存在的仓库内忽略文件：

| 路径 | 用途 | 克隆后是否必须手动提供 | 恢复方式 |
| --- | --- | --- | --- |
| `qemu-realistic/cache/noble-server-cloudimg-amd64.img` | Ubuntu 24.04 cloud base image 下载缓存 | 否 | 运行 `.\Prepare-UbuntuCloudVM.ps1` 自动下载 |
| `qemu-realistic/cache/SHA256SUMS` | Ubuntu cloud image 校验文件 | 否 | 运行 `.\Prepare-UbuntuCloudVM.ps1` 自动下载 |

这些缓存文件不是源码。克隆者只要有网络，运行准备脚本会自动重新下载并校验。

## 2. 仓库外的 VM 运行目录

当前配置文件 `vm.config.json` 把 VM 运行目录放在：

```text
D:\VMRealPC
```

这些文件不在仓库目录内，因此不是由 `.gitignore` 直接排除，但它们是当前这台已经装好系统的 VM 的实际运行产物。

| 路径 | 用途 | 克隆后是否必须手动提供 | 恢复方式 |
| --- | --- | --- | --- |
| `D:\VMRealPC\RealPC-01.qcow2` | 已安装 Ubuntu、XFCE、XRDP、Steam 的系统盘 | 重新构建不需要；想复用当前已装系统才需要 | 运行准备和安装脚本重建，或从当前机器拷贝 |
| `D:\VMRealPC\seed.iso` | cloud-init CIDATA ISO | 否 | `.\Prepare-UbuntuCloudVM.ps1` 或 `.\New-CloudInitIso.ps1` 生成 |
| `D:\VMRealPC\cloud-init\user-data` | cloud-init 用户、密码、SSH key 配置 | 否 | `.\Prepare-UbuntuCloudVM.ps1` 生成 |
| `D:\VMRealPC\cloud-init\meta-data` | cloud-init instance metadata | 否 | `.\Prepare-UbuntuCloudVM.ps1` 生成 |
| `D:\VMRealPC\ssh\id_ed25519` | SSH 私钥 | 否，且不建议共享 | `.\Prepare-UbuntuCloudVM.ps1` 自动生成新的 key |
| `D:\VMRealPC\ssh\id_ed25519.pub` | SSH 公钥 | 否 | 随私钥自动生成 |
| `D:\VMRealPC\ssh\known_hosts` | SSH known hosts 记录 | 否 | 首次 SSH 连接自动生成 |
| `D:\VMRealPC\OVMF_VARS.fd` | UEFI NVRAM 变量文件 | 否 | 启动脚本按 QEMU OVMF 模板生成或复用 |
| `D:\VMRealPC\.ubuntu-cloud-prepared` | 系统盘准备完成标记 | 否 | `.\Prepare-UbuntuCloudVM.ps1` 生成 |
| `D:\VMRealPC\qemu.pid` | 当前 QEMU 进程 PID | 否 | VM 启动时生成 |
| `D:\VMRealPC\qemu.stdout.log` | QEMU stdout 日志 | 否 | VM 启动时生成 |
| `D:\VMRealPC\qemu.stderr.log` | QEMU stderr 日志 | 否 | VM 启动时生成 |
| `D:\VMRealPC\serial.log` | Guest 串口日志 | 否 | VM 启动时生成 |

## 3. 克隆后从零恢复可运行环境

在新机器上克隆仓库后，推荐按以下流程重建本地运行产物：

```powershell
Set-Location 'D:\虚拟机\qemu-realistic'

# 安装 QEMU。已经安装过可跳过。
.\Install-QEMU.ps1

# 可选：开启 WHPX 加速，需要管理员 PowerShell 和重启。
.\Enable-WHPX.ps1 -Restart

# 下载 Ubuntu cloud image、生成系统盘、SSH key、cloud-init seed。
.\Prepare-UbuntuCloudVM.ps1

# 首次启动并注入 cloud-init。
.\Start-UbuntuCloudVM.ps1 -Provision -WaitForSsh

# 安装 XFCE、XRDP、Steam 客户端和图形依赖。
.\Setup-SteamGraphicalGuest.ps1
```

后续启动：

```powershell
Set-Location 'D:\虚拟机'
.\qemu-realistic\Start-UbuntuCloudVM.ps1 -WaitForSsh
```

连接桌面：

```powershell
mstsc /v:127.0.0.1:3390
```

运行硬件真实性检测：

```powershell
$ssh = 'C:\Windows\System32\OpenSSH\ssh.exe'
$key = 'D:\VMRealPC\ssh\id_ed25519'
$known = 'D:\VMRealPC\ssh\known_hosts'
& $ssh -o StrictHostKeyChecking=no -o "UserKnownHostsFile=$known" -i $key -p 2222 codex@127.0.0.1 '~/assess-guest-hardware-realism.sh'
```

## 4. 如果要复用当前已经装好的 VM

如果希望克隆后的机器直接使用当前这台已经安装 Steam 图形环境的 VM，需要额外迁移：

```text
D:\VMRealPC\RealPC-01.qcow2
D:\VMRealPC\OVMF_VARS.fd
D:\VMRealPC\ssh\id_ed25519
D:\VMRealPC\ssh\id_ed25519.pub
D:\VMRealPC\cloud-init\
```

注意：

- `RealPC-01.qcow2` 当前约 9 GB，后续会继续变大，不适合放入普通 git 仓库。
- `id_ed25519` 是私钥，不建议提交或共享到公开仓库。
- 如果迁移到不同路径，需要同步修改 `vm.config.json` 里的 `vm.basePath`、`vm.diskPath`、`boot.firmwareVarsPath`、`cloudImage.seedDirectory`、`cloudImage.seedIsoPath`、`cloudImage.sshKeyPath`、`cloudImage.preparedMarker`。
- 更推荐在新机器上重新运行第 3 节流程重建环境。

## 5. 需要进入 git 的文件

为了让克隆者能够按脚本重建环境，以下文件应当提交到 git：

```text
qemu-realistic/vm.config.json
qemu-realistic/Prepare-UbuntuCloudVM.ps1
qemu-realistic/New-CloudInitIso.ps1
qemu-realistic/Start-UbuntuCloudVM.ps1
qemu-realistic/Start-RealisticVM.ps1
qemu-realistic/Setup-SteamGraphicalGuest.ps1
qemu-realistic/assess-guest-hardware-realism.sh
qemu-realistic/OPERATIONS.md
qemu-realistic/LOCAL_ARTIFACTS.md
```

当前 `Setup-SteamGraphicalGuest.ps1`、`OPERATIONS.md`、`LOCAL_ARTIFACTS.md` 是克隆后可运行流程的重要文档或脚本，提交时不要遗漏。

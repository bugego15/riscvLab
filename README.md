# riscvLab — RISC-V 启动流程学习实验

在 QEMU `-M virt` 上学习 RISC-V 启动流程的代码仓库。按"五阶段启动链"组织，当前已上传
**第一 ~ 四阶段**，第五阶段（应用层 init）已开始（initramfs `/init` 已跑通）。

## 五阶段启动链

| 阶段 | 内容 | 状态 |
|---|---|---|
| **1** | 复位后第一段代码（真机 BootROM / 自写 stage0） | ✅ `01-boot-chain/00-rom/` |
| **2** | M 模式固件（SBI 提供者：OpenSBI） | ✅ `01-boot-chain/01-opensbi/` |
| **3** | 二级 loader（U-Boot，S 模式；含磁盘启动与 A/B OTA） | ✅ `01-boot-chain/03-uboot-s/`、`02-uboot-ota/` |
| **4** | 内核加载协议（Image 头 / booti / FIT / QEMU -kernel） | ✅ `01-boot-chain/05-kernel/` |
| **5** | 应用层 init（initramfs / rootfs，内核初始化 → PID1） | 🚧 `01-boot-chain/06-init/` |

## 第一阶段做什么

QEMU `virt` 复位后 `PC = 0x1000`，执行 6 条复位向量指令，然后跳到 `0x80000000`：

```
复位(M模式, PC=0x1000)
  auipc t0, 0x0          # t0 = 0x1000
  addi  a2, t0, 40       # a2 = 0x1028（fw_dynamic_info 指针）
  csrr  a0, mhartid      # a0 = hartid
  ld    a1, 32(t0)       # a1 = *(0x1020) = DTB 物理地址
  ld    t0, 24(t0)       # t0 = *(0x1018) = 下一级入口
  jr    t0               # 跳到 0x80000000
```

自写 stage0（M 模式）建栈、打印、校验 DTB magic 后把 hartid/DTB 交给 OpenSBI；
自写 stage1（S 模式）通过 SBI `ecall` 打印 SBI 版本，证明 OpenSBI 就位。

## 第二阶段做什么

0x80000000 处的 **M 模式固件（SBI 提供者）**，本仓库用 **OpenSBI v1.7**：

- 保存启动参数（hartid / DTB / fw_dynamic_info）；
- 自身初始化（scratch、栈、heap、BSS、重定位）；
- 平台发现（DTB，识别 `riscv-virtio,qemu`）；
- 最小平台设施：UART console、定时器、IPI、复位/关机、PMU；
- PMP/Domain 隔离与中断/异常委托；
- 建立 SBI 运行时（trap handler + TIME/IPI/RFENCE/HSM/SRST/DBCN…）；
- 设置 `mstatus.MPP=S`、`mepc=next_addr`，`mret` 切到 S 模式。

## 第三阶段做什么

S 模式二级 loader，本仓库用 **U-Boot v2025.10**：

- 接管 OpenSBI 的 `a0=hartid, a1=DTB`，设置异常入口；
- 自身重定位（0x80200000 → RAM 高地址 0x9f6ce000），给内核腾空间；
- FDT 解析、早期 malloc、内存预留、驱动模型（DM）、console、存储（virtio/flash）、env；
- 磁盘启动：FAT boot 分区加载 `boot.scr`，按脚本加载槽位 FIT；
- A/B OTA：`slot/upgrade_available/bootcount/bootlimit` 状态机、FIT sha256 校验、
  bootcount 超限自动回滚、env/状态持久化。

## 第四阶段做什么

**内核加载协议**（loader ↔ kernel 的 ABI），不是独立代码阶段：

| 约定 | 本实验值 |
|---|---|
| 镜像头 64B：`text_offset` | `0x200000`（2 MiB） |
| 放置地址 | `0x80000000 + 0x200000 = 0x80200000` |
| 入口 | Image 偏移 0：`c.li s4,-13; j _start_kernel`（`_start_kernel = 0xffffffff800010d8`） |
| 寄存器/模式 | `a0=hartid, a1=DTB`；S 模式；MMU 关闭 |
| 校验字段 | `magic2 = 0x05435352`（"RSC\x05"，ARM64 兼容位置） |

三种实现路径：U-Boot `booti`（按 `ram_base+text_offset` 搬移）、U-Boot `bootm`/FIT
（`load=0x80200000`+hash 校验）、QEMU `-kernel`（直接加载到 0x80200000）。

## 第五阶段做什么（已开始）

内核初始化完成后启动 **PID 1**：

- `start_kernel() → rest_init() → kernel_init → run_init_process("/init")`；
- initramfs 的 `/init`：挂载 proc/sys/dev → 打印 banner → `exec /bin/sh`；
- rootfs（A/B 分区）里的 BusyBox init：`/etc/inittab → /etc/init.d/rcS → shell`，含槽位确认与 OTA agent。

## 环境要求

- Linux / WSL2 Ubuntu（**推荐 WSL2**）
- 依赖工具：

```bash
sudo apt update
sudo apt install -y qemu-system-misc gcc-riscv64-linux-gnu gdb-multiarch make git \
  bc flex bison libssl-dev libelf-dev swig python3-dev \
  u-boot-tools mtools e2fsprogs util-linux curl
```

- 构建根默认 `~/riscv-lab`，可用环境变量覆盖：`BUILD_ROOT=/path/to/build bash ...`

## 快速开始

```bash
git clone https://github.com/bugego15/riscvLab.git
cd riscvLab

# 0) 下载源码
bash scripts/fetch-opensbi.sh     # OpenSBI v1.7（gitee 镜像）
bash scripts/fetch-sources.sh     # Linux 6.12.117 + U-Boot v2025.10（kernel.org / source.denx.de）

# ===== 第一阶段：复位后第一段代码 =====
bash 01-boot-chain/00-rom/build-rom.sh
bash 01-boot-chain/00-rom/run-stage0.sh
bash 01-boot-chain/00-rom/gdb-stage0.sh      # 可选：GDB 逐级单步

# ===== 第二阶段：M 模式固件 OpenSBI =====
bash 01-boot-chain/01-opensbi/build-opensbi.sh
bash 01-boot-chain/01-opensbi/build-payload.sh
bash 01-boot-chain/01-opensbi/run-opensbi.sh
bash 01-boot-chain/01-opensbi/gdb-handoff.sh # 可选：看 M→S 交接时刻

# ===== 第三阶段：U-Boot（S 模式）+ A/B OTA =====
bash 01-boot-chain/03-uboot-s/build-uboot-s.sh
bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
bash 01-boot-chain/03-uboot-s/gdb-reloc.sh   # 可选：看 U-Boot 入口与重定位

# ===== 第四阶段：内核加载协议 =====
bash 00-env/build-busybox.sh
bash 01-boot-chain/06-init/mk-initramfs.sh
bash 01-boot-chain/05-kernel/build-kernel.sh   # 首次编译较慢
bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh
bash 01-boot-chain/05-kernel/gdb-kernel-entry.sh  # 可选：看内核入口 a0/a1

# ===== 第三阶段（磁盘 + A/B OTA）=====
export COMPRESSION=none                      # 本实验 U-Boot 下 gzip FIT 会挂起
bash 02-uboot-ota/test-ota.sh                # 四个 OTA 场景（正常/坏包/回滚/FIT 哈希回退）
```

> 如果所在网络访问 GitHub 受限（例如 WSL 内直连被墙），可以用 gh-proxy 镜像克隆：
> `git clone https://gh-proxy.com/https://github.com/bugego15/riscvLab.git`

### 预期输出（第一阶段关键行）

```
[stage0] hartid = 0x0000000000000000
[stage0] DTB    = 0x000000009fe00000
[stage0] FDT magic (raw LE) = 0x00000000edfe0dd0
[stage0] handoff -> OpenSBI fw_jump @0x80200000
OpenSBI v1.7
Firmware Base               : 0x80200000
[stage1] SBI spec version = 0x0000000003000000
```

### 预期输出（第三阶段关键行）

```
U-Boot 2025.10
DRAM:  512 MiB
Core:  27 devices, 14 uclasses, devicetree: board
Moving Image from 0x84000000 to 0x80200000
Starting kernel ...
[    1.431584] Run /init as init process
```

### 预期输出（第五阶段：用户态 init）

```
[    0.000000] Run /init as init process
  RISC-V initramfs: userspace init (/init) 已运行
  pid=1  cmdline: console=ttyS0 earlycon keep_bootcon
```

## 目录结构

```
riscvLab/
├─ README.md
├─ 00-env/
│  └─ build-busybox.sh          构建 static BusyBox（initramfs/rootfs 用）
├─ 01-boot-chain/
│  ├─ 00-rom/                   第一阶段：复位后的第一段代码
│  ├─ 01-opensbi/               第二阶段：M 模式固件 OpenSBI
│  ├─ 03-uboot-s/               第三阶段：S 模式 U-Boot（构建/运行/GDB 重定位观察）
│  ├─ 05-kernel/                第四阶段：内核构建、启动与入口观察
│  └─ 06-init/                  第五阶段：initramfs /init
├─ 02-uboot-ota/                磁盘启动 + A/B OTA（分区/槽位/回滚/env 持久化）
└─ scripts/
   ├─ common.sh                 公共路径/版本变量
   ├─ fetch-opensbi.sh          下载 OpenSBI v1.7
   └─ fetch-sources.sh          下载 Linux 与 U-Boot 源码
```

## 说明

- 所有实验都在 QEMU `-M virt` 上完成，不依赖真实硬件。
- 本仓库是完整学习实验（启动链 / 分区 OTA / 内存 / 进程）的**第一 ~ 五阶段**摘录，后续深入实验会继续上传。
- 脚本默认把源码放在 `~/riscv-lab/src`、构建产物放在 `~/riscv-lab/build`，可用 `BUILD_ROOT` 环境变量改到其他目录。
- 已知限制：本实验 U-Boot 配置下 FAT 中的 gzip 压缩 FIT 会在解压阶段挂起，OTA 实验统一使用 `COMPRESSION=none`。

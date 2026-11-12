# RISC-V 启动流程与内存/进程：原理与测试手册（详细版）

> 本文档面向"要真正看懂并亲手验证"的读者：
> **第 2 章讲原理**（这个系统从上电到 shell 到底发生了什么，关键概念逐个解释）；
> **第 3 章讲测试**（每一级怎么跑、看什么输出、怎么判断对错、出错怎么查）。
>
> 配套文档：`docs/01-boot-flow.md`（启动链实验记录）、`02-uboot-ota.md`（分区/OTA）、
> `03-memory.md`（内存实验）、`04-process.md`（进程实验）、`05-summary.md`（总报告）。
> 证据日志在 `results/m0`–`m4`。

---

## 目录

- [0. 环境与路径约定](#0-环境与路径约定)
- [1. 系统总览](#1-系统总览)
- [2. 原理篇：一次 RISC-V 启动到底发生了什么](#2-原理篇一次-riscv-启动到底发生了什么)
  - [2.1 先建立概念：hart / 特权级 / CSR / SBI / DTB](#21-先建立概念hart--特权级--csr--sbi--dtb)
  - [2.2 QEMU virt 的"上电"：复位向量](#22-qemu-virt-的上电复位向量)
  - [2.3 五级启动链：每一级的职责与交接](#23-五级启动链每一级的职责与交接)
  - [2.4 Linux 内核内部的启动流程](#24-linux-内核内部的启动流程)
  - [2.5 内存管理原理：memblock → buddy → SLUB](#25-内存管理原理memblock--buddy--slub)
  - [2.6 进程管理原理](#26-进程管理原理)
  - [2.7 A/B OTA 原理](#27-ab-ota-原理)
  - [2.8 QEMU 与真实 SoC 的差异](#28-qemu-与真实-soc-的差异)
- [3. 测试篇：每个阶段怎么测、观察什么](#3-测试篇每个阶段怎么测观察什么)
  - [3.1 测试原则与观察工具箱](#31-测试原则与观察工具箱)
  - [3.2 阶段 0：环境自检](#32-阶段-0环境自检)
  - [3.3 阶段 M0：基线启动测试](#33-阶段-m0基线启动测试)
  - [3.4 阶段 M1：五级启动链逐级测试（含 GDB）](#34-阶段-m1五级启动链逐级测试含-gdb)
  - [3.5 阶段 M2：分区与 A/B OTA 测试](#35-阶段-m2分区与-ab-ota-测试)
  - [3.6 阶段 M3：内存测试](#36-阶段-m3内存测试)
  - [3.7 阶段 M4：进程测试](#37-阶段-m4进程测试)
  - [3.8 测试矩阵总表](#38-测试矩阵总表)
  - [3.9 常见故障与排查](#39-常见故障与排查)
- [4. 自测清单](#4-自测清单)
- [5. 最短复现路径](#5-最短复现路径)
- [6. 进一步深入的建议](#6-进一步深入的建议)

---

## 0. 环境与路径约定

| 项 | 值 |
|---|---|
| 仓库根目录 | 你 clone 的 `riscvLab` 目录（下文用 `$LAB` 表示） |
| 构建根（WSL ext4） | `~/riscv-lab`，内含 `src/ build/ images/ logs/ rootfs/ tools/` |
| 构建/运行 | WSL2 Ubuntu 24.04 内的 QEMU 8.2.2；Windows QEMU 11.1 仅做交叉验证 |
| 内核 | Linux 6.12.117（含 debug_info；release 名 `6.12.117-riscv-lab`） |
| 固件/引导 | OpenSBI 1.7、U-Boot 2025.10（源码构建的 M/S/SPL 三种） |
| 用户态 | BusyBox 1.37.0 静态（initramfs / ext4 rootfs） |

**PowerShell 里执行 WSL 脚本的两种写法：**

```powershell
# 写法 A：直接执行脚本
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/run-stage0.sh

# 写法 B：需要环境变量/管道时
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=buddy bash lab/run-lab.sh'
```

> 提醒：所有 `run-*.sh` 都会把串口输出同时写进 `~/riscv-lab/logs/`，并把关键版本复制到 `results/`。
> QEMU 全部用 `-nographic -no-reboot` 启动，日志通过 `timeout` 结束。
>
> **交互式终端小坑**：在 WSL 交互式 shell 里直接运行脚本时，QEMU 的 stdin 是终端（TTY），
> 而 stdout 被 `tee` 接成管道；这种「stdin 是 TTY、stdout 不是 TTY」的组合下，
> QEMU `-nographic` 的 stdio 串口可能完全没有输出（日志变成 0 字节）。
> 仓库脚本已统一把 QEMU 的 stdin 重定向为 `< /dev/null`。如果你手工拼 QEMU 命令
> 并把输出重定向到文件/管道，也请加 `< /dev/null`。从 PowerShell 用
> `wsl -d Ubuntu-24.04 -e bash ...` 调用时 stdin 不是 TTY，不受影响。

---

## 1. 系统总览

### 1.1 启动相关产物

| 产物 | 位置 | 说明 |
|---|---|---|
| 内核 `Image` | `~/riscv-lab/build/linux-6.12.117/arch/riscv/boot/Image` | 25MB，RISC-V Linux Image（含 64B 头） |
| 内核符号 `vmlinux` | 同目录 | 288MB，GDB 用 |
| OpenSBI `fw_dynamic.bin` / `fw_jump.bin` | `~/riscv-lab/images/` | 源码构建 1.7 |
| U-Boot M 模式 | `~/riscv-lab/images/u-boot-m.bin` | 直接作 `-bios` |
| U-Boot S 模式 | `~/riscv-lab/images/u-boot-s.bin` | 带 virtio-blk/FAT/ext4/env/FIT 支持 |
| SPL | `~/riscv-lab/images/u-boot-spl.bin` + `u-boot.itb` | 两段式引导 |
| BusyBox initramfs | `~/riscv-lab/images/initramfs.cpio.gz` | 1.2MB，M0 用 |
| lab initramfs | `~/riscv-lab/images/lab-initramfs.cpio.gz` | 3.2MB，M3/M4 实验用 |
| A/B 磁盘 | `~/riscv-lab/images/ab-disk.img` | 256MB GPT，M2 用 |

### 1.2 QEMU virt 物理地址地图（512MB 内存时）

| 物理地址 | 内容 | 谁用 |
|---|---|---|
| `0x00001000` | QEMU 内置复位向量 ROM | 复位时 PC |
| `0x00100000` | SiFive test / syscon（关机/复位） | guest `reboot -f`、`poweroff -f` |
| `0x00101000` | goldfish RTC | Linux |
| `0x01000000` | 16550 UART（串口 console） | 所有阶段 |
| `0x02000000` | CLINT（timer / IPI） | OpenSBI / Linux |
| `0x0C000000` | PLIC（外部中断） | Linux |
| `0x30000000` | PCI ECAM | Linux（本实验不使用） |
| `0x80000000` | RAM 起始（512MB：0x80000000–0x9fffffff） | 全部 |
| `0x80000000` | 固件（OpenSBI / U-Boot M）或自写 stage0 | M 模式 |
| `0x80200000` | S 模式下一级：U-Boot proper 或 Linux Image 入口 | S 模式 |
| `0x9fe00000` | QEMU 生成的 DTB（512MB 内存时靠高址） | — |

> 真实芯片会把 UART/CLINT/PLIC 换成实际外设地址；QEMU virt 的布局可以在启动日志
> `/proc/iomem` 与 `bdinfo` 里直接看到。

---

## 2. 原理篇：一次 RISC-V 启动到底发生了什么

### 2.1 先建立概念：hart / 特权级 / CSR / SBI / DTB

#### （1）hart = hardware thread（硬件线程）

RISC-V 把"一个能独立取指执行的逻辑核"叫 **hart**，用 **hartid** 编号。
QEMU 默认 `-smp 1`，所以只有 hart 0 启动；多核时每个 hart 都在复位向量处开始，
通常由固件指定一个 boot hart 继续，其余 hart 等待（本实验不展开 CPU 热插拔/SMP）。

**启动约定**：进入下一级时，`a0 = hartid`，`a1 = DTB 物理地址`。这是贯穿整条启动链的最重要约定。

#### （2）三个特权级：M / S / U

| 特权级 | 全称 | 谁运行 | 能做什么 |
|---|---|---|---|
| **M**（Machine） | 机器模式 | 固件（OpenSBI）、引导（U-Boot M 模式）、自写 stage0 | 访问所有 CSR、配置 PMP、物理内存，最高权限 |
| **S**（Supervisor） | 超级用户模式 | Linux 内核、U-Boot proper（S 模式） | 管理页表（satp）、异常/中断入口，不能碰 M 专属 CSR |
| **U**（User） | 用户模式 | 应用程序、BusyBox、shell | 只能访问自己页表映射的用户页 |

**怎么切换？** M → S 用 `mret`（`mstatus.MPP` 决定 mret 后进入哪个级别）；S → U 用 `sret`。
异常/中断进入更高特权级。QEMU 上"复位后默认在 M 模式、PC=0x1000"。

**为什么要有 OpenSBI？** 因为 Linux 内核跑在 S 模式，它不能直接操作 M 模式硬件
（时钟、IPI、串口等需要特殊权限的寄存器，由 M 模式固件通过 **SBI** 服务提供）。
OpenSBI 就是常驻 M 模式的固件：它让 Linux 用 `ecall` 请求服务（打印一个字符、设置定时器、
发送 IPI、复位系统……），自己代替内核做 M 模式操作。

#### （3）CSR：控制状态寄存器

启动交接时最常看几个：

| CSR | 含义 | 观测价值 |
|---|---|---|
| `mstatus` | M 模式状态：MIE、MPP（mret 后特权级）、MPIE… | 看固件在 M 模式做了什么、交给 S 模式前 MPP=1 |
| `sstatus` | S 模式视图：SIE、SPP… | 看 U-Boot/内核入口确实是 S 模式 |
| `satp` | 页表根：MODE（0=Bare, 8=Sv39, 9=Sv48, 10=Sv57）+ ASID + 根页表物理页号 | 看内核是否开启 MMU、用的是几级页表 |
| `stvec` / `mtvec` | 异常/陷阱入口地址 | 看 U-Boot/内核是否已安装 trap handler |
| `mie/mip` | 中断使能/挂起 | 本实验不深入中断，仅说明存在 |

GDB 里用 `info registers mstatus sstatus satp` 就能直接看到。

#### （4）SBI：S 模式二进制接口

SBI 是"内核向 M 模式固件请求服务"的标准接口：`ecall` 指令，`a7=EID`（扩展号）、
`a6=FID`（功能号）、`a0..a5` 传参，返回 `a0=错误码, a1=返回值`。
常见扩展：TIME（定时器）、IPI（核间中断）、RFENCE（远程栅栏）、SRST（复位）、DBCN（调试打印）等。
OpenSBI 启动日志会列出它支持的扩展（本实验日志里是 `Runtime SBI Version : 3.0`，
扩展含 `time,ipi,rfnc,srst,hsm,dbcn,...`）。

**分工**：Linux 内核在 S 模式运行，遇到需要 M 权限的操作通过 ecall 进入 OpenSBI；
OpenSBI 在 M 模式处理完再 `mret` 回内核。

#### （5）DTB / FDT：设备树

设备树是"硬件描述数据"（二进制格式 DTB，文本格式 DTS）。QEMU 在内存里生成一份 DTB，
启动时用 `a1` 传给下一个阶段：

- 固件（OpenSBI）会读取并可能修改它（增加 `/chosen`、reserved-memory），
- 最终内核通过 `a1` 拿到 DTB，解析出：CPU 核数、内存大小、串口地址、中断控制器、
  virtio 设备信息（磁盘）、`/chosen/bootargs`（内核命令行）等。

常用命令：

```bash
# 把 QEMU 生成的 DTB 存下来并反编译查看
qemu-system-riscv64 -M virt,dumpdtb=virt.dtb -m 512M -nographic
dtc -I dtb -O dts virt.dtb | head -80
# 从正在运行的 Linux 里看
dtc -I fs -O dts /sys/firmware/devicetree/base | head
```

本实验里 QEMU 生成的 DTB 大小约 4342 字节，magic 是大端 `0xd00dfeed`
（小端按 u32 读出来是 `0xedfe0dd0`，stage0 实验里会打印它来验证 a1 有效）。

#### （6）镜像格式：Linux Image、uImage/uInitrd、FIT

| 格式 | 结构 | 谁生成/谁消费 |
|---|---|---|
| **Linux Image**（RISC-V） | 开头 64 字节头（magic/text_offset/image_size/flags…）+ 内核代码。`text_offset=0x200000` 表示期望加载到 RAM 起始 + 2MB = `0x80200000` | 内核构建产物；QEMU `-kernel`、U-Boot `booti`/FIT 消费 |
| **legacy uImage** | 64 字节头（magic 0x27051956、类型、压缩方式、数据长度、校验和）+ 数据 | `mkimage -T kernel/ramdisk` 生成；U-Boot `bootm` 消费 |
| **uInitrd** | 就是"ramdisk 类型的 uImage"（内含 gzip cpio） | U-Boot `booti` 的 ramdisk 参数**要求**这种格式（本实验踩过坑） |
| **FIT**（Flattened Image Tree） | 用 DTS 描述的镜像集合：可含 kernel、dtb、ramdisk、每个带 sha256/签名；U-Boot `bootm` 统一校验后启动 | `mkimage -f xxx.its xxx.itb`；U-Boot `bootm` 消费 |
| **boot.scr** | U-Boot 脚本（`mkimage -T script` 打包），内容是 U-Boot 命令序列 | U-Boot `source` 执行 |

#### （7）MMU 与页表（后面内存章节详述）

S 模式内核通过 `satp` 启用分页。RISC-V 64 位支持 Bare / Sv39 / Sv48 / Sv57（3/4/5 级页表）。
QEMU 的 CPU 支持 Sv57，本实验内核实际运行在 **Sv57（5 级）**。
页表项（PTE）典型位：`V`（有效）、`R/W/X`（读/写/执行）、`U`（用户可访问）、`G`（全局）、
`A/D`（访问/脏位）、以及高位物理页号 PPN。

---

### 2.2 QEMU virt 的"上电"：复位向量

真实芯片上电后从 BootROM 固定地址开始执行。QEMU virt **没有真实 BootROM**，
但提供了一个**复位向量桩**：复位时 PC = `0x1000`，`0x1000` 处的几条指令做三件事：

```
0x1000: auipc t0, 0x0
0x1004: addi  a2, t0, 40      # a2 = 动态信息地址（QEMU 的 fw_dynamic info）
0x1008: csrr  a0, mhartid     # a0 = hartid
0x100c: ld    a1, 32(t0)      # a1 = DTB 物理地址
0x1010: ld    t0, 24(t0)      # t0 = 固件入口地址（默认 0x80000000）
0x1014: jr    t0              # 跳到固件
```

这段代码是我们在 M1 的 GDB 实验里**逐条单步**看到的（`results/m1/m1-a0-gdb-transcript.log`）。
单步 6 条后：`pc=0x80000000, a0=0(hartid), a1=0x9fe00000(DTB)`。

**与真实芯片的差距**：真实 BootROM 还要 DDR 初始化、从 SPI Flash/eMMC 读第一级镜像、
校验、设置时钟等；QEMU 的 ROM 桩不做这些。这正是要用"自写 stage0"补足理解的地方。

---

### 2.3 五级启动链：每一级的职责与交接

把"启动方式的选择"拆成 5 个可选点。同一个内核/同一个用户态，替换任意一级即可对照。

#### 选择点 1：复位后第一段代码（BootROM 的替身）

| 方案 | 做法 | 职责 |
|---|---|---|
| (a) QEMU 内置复位向量 | 什么都不写，`-bios` 直接给固件 | 桩：取 hartid/DTB、跳固件 |
| (b) 自写 stage0 | 把 1.8KB 的 M 模式程序作为 `-bios` 加载到 0x80000000 | 建栈、初始化 UART、打印 hartid/DTB、校验 FDT magic、**原样传递 a0/a1** 后跳下一级 |

自写 stage0 的源码在 `01-boot-chain/00-rom/stage0.S` + `stage0.c`；它演示了
"BootROM 到底该干什么"——打印/校验/传参/跳转，是我们理解启动链的锚点。

#### 选择点 2：M 模式固件（SBI 提供者）

| 方案 | 命令要点 | 说明 |
|---|---|---|
| **OpenSBI `fw_dynamic`** | `-bios fw_dynamic.bin -kernel u-boot.bin` | QEMU 把"下一级地址/DTB/模式"放在动态信息里（a2 指向），OpenSBI 读取后启动下一级 |
| **OpenSBI `fw_jump`** | `-bios fw_jump.bin -kernel Image` | 固定跳转地址（编译时决定，本实验为 0x80200000），最常用 |
| **OpenSBI `fw_payload`** | 把内核直接嵌进固件 | 单文件镜像，适合产品化 |
| **U-Boot M 模式** | `-bios u-boot.bin`（M 模式构建） | 无 OpenSBI，U-Boot 自己承担 M 模式职责（现代 RISC-V 不推荐） |

**OpenSBI 做的事**（启动日志可见）：初始化 M 模式 trap、PMP（保护自己的内存区域）、
设备（串口/CLINT）、创建 Domain（给 S 模式划分可用物理区域）、打印版本信息，
最后设置 `mstatus.MPP = S` 并 `mret` 到下一级地址（0x80200000），同时传 a0=hartid、a1=DTB。

启动日志里重点看：

```
Firmware Base        : 0x80000000
Runtime SBI Version  : 3.0
Domain0 Next Address : 0x0000000080200000   ← 下一级入口
Domain0 Next Arg1    : 0x000000009fe00000   ← 传给下一级的 DTB（可能被改写）
Domain0 Next Mode    : S-mode
```

#### 选择点 3：二级 loader

| 方案 | 组成 | 说明 |
|---|---|---|
| **U-Boot proper（S 模式）** | OpenSBI（M）→ U-Boot proper（S，0x80200000） | 标准做法；U-Boot 负责驱动/文件系统/命令/加载内核/OTA |
| **U-Boot SPL 两段式** | SPL（M）→ 加载 `u-boot.itb`（内含 OpenSBI `fw_dynamic` + U-Boot proper）→ OpenSBI → proper | 贴近真实 SoC "ROM→SPL→U-Boot"；QEMU 上 SPL 的"加载下一级"由 `-device loader` 模拟 |
| **自写 loader** | stage0(M) → 定制 OpenSBI(0x80200000) → 自写 S 模式 payload(0x80400000) | A0 实验，用来证明"交接协议"而不是依赖现成软件栈 |

U-Boot 起来后，它自己会打印：

```
U-Boot 2025.10 ...
Model: riscv-virtio,qemu
DRAM:  512 MiB
Loading Environment from FAT... OK       ← env 从 virtio-blk FAT 读取（M2 验证点）
```

U-Boot 的第一条指令处（GDB 观察）：`mv tp,a0; mv s1,a1; li gp,0; ... csrw stvec,t0`，
即"保存 hartid、保存 DTB 指针、清 gp、安装 trap 向量"。

#### 选择点 4：内核加载协议

| 方案 | 命令/流程 | 特点 |
|---|---|---|
| **QEMU 直接 `-kernel`** | `-bios fw_jump.bin -kernel Image` | 绕过 U-Boot；QEMU 负责把 Image 放到 0x80200000；本实验 M0/A4-GDB 用它 |
| **U-Boot `booti`** | `boot.scr` 里 `fatload virtio 0:1 0x84000000 Image`、`fatload ... 0x8c300000 initramfs.uimg`、`booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdtcontroladdr}` | U-Boot 按 Image 头 `text_offset` **把内核从加载地址搬到 0x80200000**（日志：`Moving Image from 0x84000000 to 0x80200000`） |
| **U-Boot `bootm` + FIT** | `fatload ... 0x88000000 slot_a.itb`、`bootm 0x88000000` | FIT 内 kernel+dtb 带 sha256；U-Boot 校验通过后才启动；坏镜像会校验失败（M2 场景） |

内核入口约定：`pc=0x80200000, a0=hartid, a1=DTB 物理地址`。
注意：走 OpenSBI 的路径里，DTB 可能已经被 OpenSBI 从 0x9fe00000 搬到 0x82200000
（`-kernel` 直启时实测 a1=0x82200000；用 FIT 时 DTB 在 FIT 内部，bootm 会重新放置）。

#### 选择点 5：应用层 init

| 方案 | 机制 | 本实验 |
|---|---|---|
| **initramfs** | 内核把 cpio.gz 解压到 rootfs，然后执行 `/init`（PID 1）；成功后释放 initramfs 内存 | M0/A4：`/init` 挂 proc/sys/dev 后进入 shell |
| **rootfs（ext4）** | `root=/dev/vda2`，内核挂载后执行 `/sbin/init` | M2：BusyBox init → `/etc/inittab` → `::sysinit:/etc/init.d/rcS` → 应用/OTA → `::askfirst:/bin/sh` |

应用层初始化完成后，你的 shell/服务进程就是用户态程序的起点。
内核到这一步的关键日志：`Run /init as init process`（或 `Run /sbin/init as init process`）。

---

### 2.4 Linux 内核内部的启动流程

内核 Image 的第一条指令在 `0x80200000`，对应内核源码 `arch/riscv/kernel/head.S`：
它建立早期页表、启用 MMU、跳到高地址虚拟空间的 `start_kernel`。

```
_start (head.S)
  → 建立 fixmap/早期页表（Sv39/48/57 由 CPU 能力决定）
  → 切换到虚拟地址
start_kernel()
  → setup_arch()       解析 DTB、earlycon、memblock 记录物理内存、保留 kernel/initrd/DTB 区域
  → paging_init()      正式页表、直接映射、页表页分配、vmemmap
  → mm_init()          buddy 初始化（free_area_init）、SLUB 初始化
  → rest_init()         创建 kthreadd（PID 2）和 kernel_init（PID 1）
kernel_init()
  → do_basic_setup()   运行各级 initcall（驱动、文件系统、网络……）
  → free_initmem()
  → run_init_process("/init" 或 "/sbin/init")
```

启动日志对应关系（`results/m0/m0-kernel-initramfs.log`、`results/m3/lab-meminit.log`）：

| 日志 | 对应阶段 |
|---|---|
| `SBI specification v3.0 detected` | 内核确认 OpenSBI 在 M 模式可用 |
| `earlycon: ns16550a0 at MMIO 0x10000000` | 串口初始化，之后才能看到日志 |
| `OF: reserved mem: 0x80000000..0x8003ffff ...` | DTB 里 OpenSBI 的保留内存（M 模式固件区域） |
| `Zone ranges / Early memory node / Initmem setup` | setup_arch / memblock 阶段 |
| `Virtual kernel memory layout / lowmem */ vmemmap` | paging_init 建立的地址空间布局 |
| `Memory: ... available` | 内存账本汇总 |
| `SLUB: HWalign=64, Order=0-3 ...` | 分配器初始化 |
| `Freeing unused kernel image (initmem) memory` | init 段释放，即将进用户态 |
| `Run /init as init process` | 内核执行用户态 init |

---

### 2.5 内存管理原理：memblock → buddy → SLUB

#### （1）三层结构

```
物理内存
  │ ① 启动早期
  ▼
memblock：两个集合 memory[]（可用）和 reserved[]（被占用）
  │  - memblock_add() 记录可用 RAM
  │  - memblock_reserve() 保留 kernel/initrd/DTB/固件区
  │  - memblock_alloc() 给页表、struct page 等早期分配
  │  ↓ paging_init/mm_init 之后交接
  ▼
buddy（页分配器）：把空闲页按 2^order 组织在 zone（本机 DMA32）的 free_area[order] 里
  │  - 分配 order-n 时，若没有直接可用的块，就分裂更大的块（伙伴算法）
  │  - 每 CPU 有页缓存（pcp）缓冲低 order 分配，所以低 order 分配经常"看不到" buddyinfo 变化
  │  - 迁移类型（migratetype）把页按可移动性分链表，减少碎片
  ▼
SLUB（小对象分配器）：每个 kmem_cache 管理一类固定大小对象，slab = 一页/多页
  - 内核对象（task_struct、inode、网络包……）都走 SLUB
  - /proc/slabinfo、/sys/kernel/slab/<cache>/ 可观察
```

#### （2）页表 walk 原理

给定虚拟地址 VA 和 `satp` 根页表物理地址：
- 根据 `satp.MODE` 确定层数（Sv39=3 层、Sv48=4 层、Sv57=5 层）；
- 每层取 VA 的 9 个位作索引，读出 PTE；若 PTE 的 R/W/X 全 0 说明是中间表，继续下一层；
- 直到某层 PTE 的 R/W/X 非 0（叶子页），用 PTE 的 PPN + 页内偏移算出物理地址；
- 权限位 V/R/W/X/U/G/A/D 决定访问行为。

本实验 QEMU 默认运行在 Sv57，`satp` 的根页表物理地址与 `mm->pgd` 的物理地址一致。

#### （3）COW（写时复制）

`fork()` 不会复制全部内存页，而是让父子共享同一物理页、都映射为只读；
子进程写某页时触发 **page fault**，内核才复制这一页并给写者映射可写权限。
可以用 `/proc/self/smaps_rollup` 在用户态观察页属性（Private_Dirty/Rss 等）。

---

### 2.6 进程管理原理

- **task_struct**：内核里描述一个进程/线程的结构，包含 pid/tgid、状态、`mm`（用户地址空间）、
  `stack`（内核栈）、父子关系、调度信息等。
- **PID 1 = init**：由内核创建，负责用户态初始化（本实验的 initramfs `/init` 或 rootfs 的 `/sbin/init`）。
- **PID 2 = kthreadd**：所有内核线程的父进程；内核线程 `mm = NULL`（借用上一个用户进程的页表，叫 `active_mm`）。
- **fork**：复制进程（页表 + COW），**exec**：替换用户态映像，**wait**：回收子进程退出状态。
- **调度器**：Linux 6.12 默认 EEVDF；每一次任务切换都会触发 `sched_switch` tracepoint，
  其中 prev_state 能看出任务为什么让出 CPU（R=运行、S=睡眠、D=不可中断等）。

---

### 2.7 A/B OTA 原理

#### （1）分区布局（256MiB GPT）

| 分区 | 大小 | 文件系统 | 内容 |
|---|---|---|---|
| p1 | 64MiB | FAT16 | `boot.scr`（启动脚本）、`slot_a.itb`/`slot_b.itb`（FIT：内核+DTB+sha256）、`uboot.env`（U-Boot 环境） |
| p2 | 48MiB | ext4 | rootfs_a（BusyBox init，槽 A） |
| p3 | 48MiB | ext4 | rootfs_b（槽 B，升级目标） |
| p4 | 32MiB | ext4（无 metadata_csum） | `ota.env`（升级状态）+ OTA 包（rootfs_b.img.gz + sha256 + do-ota 标记） |

为什么 data 分区要特殊格式化：U-Boot 的 ext4 写入不支持 `metadata_csum/64bit/orphan_file`，
不关掉这些特性会报 `Unsupported RO compat features`。

#### （2）boot.scr 状态机（每次上电执行）

```
1. 从 p4 读 ota.env → env import（得到 slot / upgrade_available / bootcount / bootlimit）
2. 若 upgrade_available=1：
     bootcount += 1
     若 bootcount > bootlimit：
         切到另一个槽；upgrade_available=0；bootcount=0   ← ROLLBACK
     把状态 env export → 写回 p4（掉电后仍保持）
3. 按 slot 选择 slot_a.itb / slot_b.itb 和 root=/dev/vda2 或 /dev/vda3
4. fatload FIT → bootm（FIT 内 sha256 校验，失败则换另一个槽）
5. 启动失败（内核 panic/复位）→ 下次上电重复 2，直到超过 bootlimit 自动回退
```

#### （3）用户态 OTA agent（在旧槽 rootfs 里运行）

```
sha256sum 校验包 → gunzip -c 包 | dd of=/dev/vda3（写非活动槽）
→ 写 /data/ota.env：slot=b, upgrade_available=1, bootcount=0, bootlimit=3
→ reboot -f
```

新槽启动成功后，rootfs 的 rcS 会再次写 `ota.env`：`slot=b, upgrade_available=0, bootcount=0`
（"确认升级成功，清除待升级标记"）。如果新槽起不来，就不会执行到这一步，
bootcount 会在每次上电继续累加，最终触发 U-Boot 回退。

#### （4）两个关键机制

- **FIT 哈希校验**：FIT 里 kernel/dtb 各有 `hash@1 { algo="sha256"; }`，U-Boot `bootm` 会先校验，
  镜像被篡改/下载不完整时直接失败（本实验用 corruptfit 场景演示自动换槽）。
- **env 持久化**：U-Boot 的 env 存在 FAT 的 `uboot.env` 文件里（`saveenv` 生成），
  重启后 `Loading Environment from FAT... OK` 读回。必须禁用 `ENV_IS_NOWHERE`，否则 saveenv 会写"nowhere"。

---

### 2.8 QEMU 与真实 SoC 的差异

| 方面 | QEMU 实验 | 真实 SoC |
|---|---|---|
| BootROM | 复位向量桩（6 条指令） | DDR 初始化、Flash 读取、校验、掉电时序 |
| SPL 的"加载下一级" | `-device loader` 提前把镜像放进 RAM | SPL 自己从 eMMC/SPI NOR 读 |
| 存储 | virtio-blk（半虚拟化设备） | eMMC/UFS/SPI NOR + 真实控制器时序 |
| 看门狗/掉电 | guest `reboot -f` + QEMU `-no-reboot` 模拟 | 硬件 WDT、PMIC、掉电保持 |
| OTA 安全 | sha256 完整性 + FIT hash | 签名、dm-verity、防回滚、差分升级 |
| 中断/虚拟化 | 作为黑盒 | PLIC/CLINT 细节、H 扩展、iommu 等 |

结论：**启动链的"控制流/交接协议/地址布局/分区与 OTA 状态机"可以在 QEMU 学到；**
"外设、时序、真实 ROM 代码、掉电行为"必须在真机上补。这正是本实验的取舍。

---

## 3. 测试篇：每个阶段怎么测、观察什么

### 3.1 测试原则与观察工具箱

**测试原则**：每个实验都要回答三个问题——
1. 这一步的"输入"是什么（谁把什么放到哪里、寄存器是什么）？
2. 我"看到"了什么（串口日志/寄存器/内存/磁盘内容）？
3. 怎么判断"对"（期望值/通过标准）？

**观察工具箱**：

| 工具 | 用途 | 示例 |
|---|---|---|
| 串口日志 | 所有阶段的 printf/printk/dmesg | 每个 `run-*.sh` 都会保存到 `~/riscv-lab/logs/` |
| QEMU `-S -s` + gdb-multiarch | 单步/断点、看寄存器、看内存 | `gdb-stage0.sh`、`gdb-uboot-s.sh`、`gdb-kernel-entry.sh` |
| QEMU `-d in_asm,int,guest_errors -D qemu.log` | 反汇编执行流、异常 | 排查"跳到哪去了" |
| `dtc` + `dumpdtb` | 看设备树 | `-M virt,dumpdtb=virt.dtb` |
| `/proc`、sysfs、debugfs、tracefs | 运行时状态 | `/proc/buddyinfo`、`/proc/slabinfo`、`/sys/kernel/debug/memblock` |
| `sfdisk`/`mdir`/`debugfs` | 离线检查磁盘镜像 | 看分区表、FAT 文件名、ext4 里的 ota.env |
| `mkimage -l`/`dumpimage -l` | 看 uImage/FIT 结构 | 确认 FIT 内 kernel/dtb/hash |

> 重要习惯：QEMU 一律加 `-nographic -no-reboot`，用 `timeout` 控制运行时长；
> 日志先看有没有关键字（Linux version / Run /init / LAB BOOT OK / Redzone / panic），再看细节。

---

### 3.2 阶段 0：环境自检

**命令：**

```powershell
wsl -d Ubuntu-24.04 -e bash 00-env/check-env.sh
```

**期望输出（关键行）：**

```
OK   qemu-system-riscv64        /usr/bin/qemu-system-riscv64
OK   riscv64-linux-gnu-gcc      /usr/bin/riscv64-linux-gnu-gcc
OK   gdb-multiarch              /usr/bin/gdb-multiarch
/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin
/usr/lib/u-boot/qemu-riscv64/u-boot.bin /usr/lib/u-boot/qemu-riscv64_smode/u-boot.bin
BUILD_ROOT=~/riscv-lab
```

**判读**：全部 `OK` 且构建根/源码存在即可。若缺工具，执行
`sudo` 或 `wsl -d Ubuntu-24.04 -u root -e bash 00-env/setup-wsl.sh` 重装。

---

### 3.3 阶段 M0：基线启动测试

目标：确认"环境 → 固件 → 引导 → 内核 → 用户态"最短链能跑通。

#### 3.3.1 M 模式 U-Boot（无 OpenSBI）

```powershell
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/run-uboot-m.sh
```

**观察点**：
- `U-Boot 2025.10 ...`、`CPU: riscv`、`Model: riscv-virtio,qemu`、`DRAM: 512 MiB`；
- `Loading Environment from nowhere... OK`（说明没有 env 存储后端）；
- 出现 `=>` 提示符（U-Boot 命令行）即通过。

**判读**：U-Boot 直接作为固件在 M 模式跑；没有 OpenSBI 打印。日志：`results/m1/m1-a2-uboot-m-mode.log`。

#### 3.3.2 OpenSBI + S 模式 U-Boot

```powershell
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
```

**观察点（按顺序出现）**：
1. OpenSBI 横幅 + `Platform Name : riscv-virtio,qemu`；
2. `Firmware Base : 0x80000000`；
3. `Domain0 Next Address : 0x0000000080200000`、`Domain0 Next Mode : S-mode`；
4. U-Boot 横幅、`DRAM: 512 MiB`；
5. `=>` 提示符。

**判读**：第 3 条是"交接"的直接证据（OpenSBI 在 M 模式，下一级 0x80200000 进 S 模式）。
日志：`results/m1/m1-a1-opensbi-uboot-s.log`。

#### 3.3.3 Linux + BusyBox initramfs 到 shell

```powershell
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh
```

**观察点（关键行）**：

```
OpenSBI v1.7 ...
Domain0 Next Address : 0x80200000
[    0.000000] Linux version 6.12.117-riscv-lab ...
[    0.000000] SBI specification v3.0 detected
[    0.000000] earlycon: ns16550a0 at MMIO 0x0000000010000000
[    0.000000] Memory: 472172K/524288K available
[    0.690067] Run /init as init process
  RISC-V initramfs: userspace init (/init) 已运行
  pid=1  cmdline: console=ttyS0 earlycon keep_bootcon
/ # uname -a
Linux (none) 6.12.117-riscv-lab ... riscv64 GNU/Linux
/ # poweroff -f
[   14.632253] reboot: Power down
```

**判读**：
- `Run /init` 是"内核 → 用户态"的关口；
- shell 能执行 `uname`/`cat /proc/...` 说明用户态完全可用；
- 日志最后 `reboot: Power down` 且 QEMU 退出 = 正常结束。

#### 3.3.4 Windows QEMU 交叉验证（可选）

```powershell
$q = 'C:\Program Files\qemu\qemu-system-riscv64.exe'
# 先把产物从 WSL 复制到 Windows 目录（示例：D:\riscv-artifacts）
$d = 'D:\riscv-artifacts'
& $q -M virt -m 512M -display none -serial "file:$d\win-check.log" -no-reboot `
  -bios "$d\fw_jump.bin" -kernel "$d\Image" -initrd "$d\initramfs.cpio.gz" `
  -append "console=ttyS0 earlycon"
# 15 秒后关闭 QEMU，检查 win-check.log 里是否有 "Run /init as init process"
```

**判读**：同一份 Image/initramfs 在 Windows QEMU 11.1 也能启动到用户态，说明产物不依赖 WSL 环境。

---

### 3.4 阶段 M1：五级启动链逐级测试（含 GDB）

#### 3.4.1 A0：自写 stage0 → OpenSBI → 自写 S 模式 payload

```powershell
# 构建 stage0/stage1 + 定制地址的 OpenSBI（只需一次）
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/build-rom.sh
# 运行
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/run-stage0.sh
```

**期望输出（节选）：**

```
[stage0] self-written first-stage code (BootROM substitute)
[stage0] privilege: M-mode, load addr: 0x80000000
[stage0] hartid = 0x0000000000000000
[stage0] DTB    = 0x000000009fe00000
[stage0] FDT magic (raw LE) = 0x00000000edfe0dd0
[stage0] FDT totalsize (raw LE) = ...
[stage0] handoff -> OpenSBI fw_jump @0x80200000
OpenSBI v1.7
Firmware Base               : 0x80200000
Domain0 Next Address        : 0x0000000080400000
Domain0 Next Mode           : S-mode
[stage1] self-written S-mode payload @0x80400000
[stage1] this proves OpenSBI is already running (SBI ecall works)
[stage1] SBI spec version = 0x0000000003000000
[stage1] SBI impl id      = 0x0000000000000001
[stage1] SBI impl version = 0x0000000000010007
```

**判读**：
- `hartid=0`、`DTB=0x9fe00000`、FDT magic 正确 → 复位向量/传参链路正确；
- `Firmware Base=0x80200000`、`Next Address=0x80400000` → 定制 OpenSBI 的两个地址符合预期；
- stage1 打印 `SBI spec=0x3000000`（3.0）、`impl id=1`（OpenSBI）、`impl version=0x10007`（1.7）
  → S 模式代码通过 `ecall` 成功调用 OpenSBI 的服务，**证明 SBI 真的在工作**。

#### 3.4.2 A0-GDB：逐级单步（理解交接协议的关键）

```powershell
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/gdb-stage0.sh
```

脚本内部：QEMU 加 `-S -s`（暂停并开 gdb 端口 1234），gdb 连接后：

| 观察步骤 | 期望看到 | 说明 |
|---|---|---|
| 复位时 `info registers pc a0 a1 mstatus` | `pc=0x1000, a0=0, a1=0`（或未设置） | QEMU 复位向量入口 |
| `x/8i $pc` | `auipc/addi/csrr a0,mhartid/ld a1,.../ld t0,.../jr t0` | 复位 ROM 的 6 条指令 |
| 单步 6 次 | `pc=0x80000000, a0=0, a1=0x9fe00000` | 进入 stage0，传参已完成 |
| 断点 `0x80200000` advance | OpenSBI 入口：`mstatus` 为 M 模式 | 固件运行在 M |
| 断点 `0x80400000` advance | stage1 入口：`sstatus` 为 S 模式 | 已切到 S 模式 |

**判读**：寄存器快照 `pc/sp/a0/a1/mstatus/sstatus` 就是"交接协议"的硬证据。
你也可以手工连 GDB 改断点：

```bash
gdb-multiarch -q
(gdb) set architecture riscv:rv64
(gdb) target remote :1234
(gdb) b *0x80200000
(gdb) c
(gdb) info registers pc sp a0 a1 mstatus
```

#### 3.4.3 A1/A2/A3：三种 loader 变体

```powershell
# 源码构建（只需一次）
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/01-opensbi/build-opensbi.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/build-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/build-uboot-m.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/04-spl/build-uboot-spl.sh
# 运行
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/run-uboot-m.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/04-spl/run-spl.sh
```

**判读要点**：

| 实验 | 期望 | 说明 |
|---|---|---|
| A1 | OpenSBI 横幅 → U-Boot 横幅 → `=>` | 标准 M→S 链 |
| A2 | 没有 OpenSBI 横幅，U-Boot 直接起；`Loading Environment from nowhere` | U-Boot 自己跑 M 模式 |
| A3 | 先 `U-Boot SPL 2025.10 (...)`，再 `U-Boot 2025.10 (...)` | SPL 两段式的直接证据 |

A3 的 QEMU 命令如下（`-device loader` 把 u-boot.itb 放到 0x80200000 供 SPL 加载）：

```bash
qemu-system-riscv64 -M virt -m 512M -nographic -no-reboot \
  -bios images/u-boot-spl.bin \
  -device loader,file=images/u-boot.itb,addr=0x80200000
```

#### 3.4.4 A4：U-Boot 从 virtio-blk 加载内核（booti）

```powershell
# 生成 64MB 启动盘（FAT 分区：Image + initramfs.uimg + boot.scr）
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/mk-boot-disk.sh
# 启动
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/run-disk-boot.sh
```

**期望日志（关键顺序）**：

```
U-Boot 2025.10 ...
Loading Environment from FAT... Unable to read "uboot.env" ...   ← 首次启动没有 env 文件，正常
Hit any key to stop autoboot: 0
1133 bytes read in ...                                          ← boot.scr 加载成功
## Executing script at 8e000000
=== [boot.scr] U-Boot 启动脚本：从 virtio-blk FAT 分区加载内核 ===
--- fatload Image -> 0x84000000
25308160 bytes read in ...
--- fatload initramfs.uimg -> 0x8c300000
1247748 bytes read in ...
--- booti kernel=0x84000000 ramdisk=0x8c300000 fdt=9eeb08e0
Moving Image from 0x84000000 to 0x80200000, end=0x81aa4000   ← 按 text_offset 重定位
## Loading init Ramdisk from Legacy Image ...
...
[    0.000000] Linux version 6.12.117-riscv-lab ...
[    1.445788] Run /init as init process
  RISC-V initramfs: userspace init (/init) 已运行
```

**判读**：
- `boot.scr` 执行、两个 `fatload` 成功 = U-Boot 的文件系统/块设备驱动可用；
- `Moving Image ... to 0x80200000` = RISC-V Image 头 `text_offset` 协议生效；
- `Run /init` = 内核成功接管。

**常见失败与对策**（本实验都真实踩过）：

| 现象 | 原因 | 对策 |
|---|---|---|
| `Wrong Ramdisk Image Format` | `booti` 要求 ramdisk 是 uInitrd 格式 | `mkimage -T ramdisk -C gzip` 打包 initramfs 后再加载 |
| `Failed to reserve memory for fdt` | QEMU RISC-V 默认 `fdt_high=~0`，U-Boot 把自己的控制 FDT 传给内核 | boot.scr 里 `setenv fdt_high`（unset）让 U-Boot 自动重定位 |
| `booti` 后无任何内核输出 | 内核没被搬到 0x80200000 / DTB 无效 | 检查 `Moving Image` 行、检查 a1/DTB 地址 |

#### 3.4.5 A4-GDB：内核入口观测

```powershell
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/gdb-kernel-entry.sh
```

**期望**：在 `0x80200000` 命中内核入口，`a0=0(hartid)`、`a1=0x82200000`（OpenSBI 重定位后的 DTB），
以及 vmlinux 符号地址（`start_kernel/setup_arch/paging_init/mm_init`）。

**判读**：这是内核启动协议的直接证据：谁在什么特权级、从哪个地址、带着什么参数进入内核。

#### 3.4.6 如何切换启动方式（5 个选择点）

脚本用环境变量支持替换（不写死）：

| 替换对象 | 环境变量 | 示例 |
|---|---|---|
| OpenSBI fw | `FW_DYNAMIC` / `FW_JUMP` | `FW_JUMP=~/riscv-lab/images/fw_jump.bin ...` |
| U-Boot 变体 | `UBOOT_M` / `UBOOT_S` | `UBOOT_S=.../u-boot-s.bin` |
| 内核 Image | `KERNEL`（lab）/ 脚本内 `$KOUT` | 重新 build-kernel 后自动生效 |
| 磁盘/分区 | `SCENARIO`（mk-ab-disk.sh） | `SCENARIO=normal` |
| 实验模式 | `LAB_MODE`（lab/run-lab.sh） | `LAB_MODE=buddy` |

自己想拼 QEMU 命令时，按 `2.3` 的五种组合直接写 `-bios/-kernel/-device loader` 即可。

---

### 3.5 阶段 M2：分区与 A/B OTA 测试

#### 3.5.1 构建并检查磁盘镜像（离线检查）

```bash
cd ~/riscv-lab
SCENARIO=none bash 02-uboot-ota/mk-ab-disk.sh

# ① 看分区表（GPT，4 个分区）
sfdisk -l images/ab-disk.img

# ② 抽出 FAT 分区看内容（偏移 1MiB，64MiB）
dd if=images/ab-disk.img of=/tmp/fat.img bs=1M skip=1 count=64 status=none
mdir -i /tmp/fat.img ::/        # 应看到 boot.scr / slot_a.itb / slot_b.itb

# ③ 抽出 data 分区看 OTA 状态（偏移 161MiB，32MiB）
dd if=images/ab-disk.img of=/tmp/data.img bs=1M skip=161 count=32 status=none
debugfs -R "ls -l /" /tmp/data.img
debugfs -R "cat /ota.env" /tmp/data.img
```

**判读**：分区表 4 项类型/大小正确；FAT 里 3 个文件；data 分区 ext4 可读（没有 `metadata_csum` 的报错）。

#### 3.5.2 单次启动观察 boot.scr

```bash
TAG=base MAX_BOOTS=1 bash 02-uboot-ota/run-ab-boot.sh
```

**期望日志顺序**（`~/riscv-lab/logs/ab-base/boot1.log`）：

```
Loading Environment from FAT... Unable to read "uboot.env" ...    ← 首次
=== [boot.scr] RISC-V A/B boot flow ===
[boot.scr] no ota.env yet (first boot)
[boot.scr] >>> booting slot A: slot_a.itb, root=/dev/vda2
fatload ...
## Loading kernel (any) from FIT Image ...
   Verifying Hash Integrity ... sha256+ OK
   Uncompressing Kernel Image to 80200000
Starting kernel ...
[    2.378207] VFS: Mounted root (ext4 filesystem) on device 254:2
  RISC-V rootfs slot: a
  LAB BOOT OK: slot a
```

**判读**：boot.scr 执行成功、FIT 校验 OK、内核挂载 ext4 rootfs（254:2 = /dev/vda2）、
BusyBox init 的 rcS 打印 `LAB BOOT OK: slot a`。guest 还会把 `ota.env` 写回 data 分区。

#### 3.5.3 四个场景一键测试

```bash
COMPRESSION=none bash 02-uboot-ota/test-ota.sh
```

（`COMPRESSION=none` 可以省略，脚本默认就是未压缩 FIT。）

**每个场景的观察点与通过标准：**

| 场景 | 看什么日志 | 通过标准 |
|---|---|---|
| normal 正常升级 | boot1：`checksum OK, writing inactive slot B` → `ota.env updated (pending upgrade...)`；boot2：`ota state: slot=b upgrade=1 bootcount=0/3` → `pending upgrade attempt: bootcount=1/3` → `state saved` → `booting slot B` → `LAB BOOT OK: slot b` | 最终 `final-ota.env`：`slot=b / upgrade_available=0 / bootcount=0` |
| bad 坏包拒绝 | boot1：`expected hash ... actual hash ...` → `OTA REJECTED: checksum mismatch`；随后 `LAB BOOT OK: slot a` | 仍从 A 启动，ota.env 保持 `slot=a / upgrade=0` |
| rollback 坏镜像回退 | boot1 A 安装坏包；boot2/3/4：`bootcount=1/3,2/3,3/3` + `LAB BOOT FAIL`；boot5：`bootcount=4/3` → `!!! ROLLBACK -> slot a` → `state saved` → `LAB BOOT OK: slot a` | 第 5 次上电回到 A，`final-ota.env：slot=a / upgrade=0` |
| fit_hash_fallback 哈希回退 | boot1：`bootm failed for slot A (bad FIT/hash); trying other slot` → 加载 B → `LAB BOOT OK: slot b` | 自动换槽成功；final-ota.env 的 slot=b |

**判读技巧**：先 `grep -E 'boot.scr|ota-agent|LAB BOOT|ROLLBACK|bootm failed' 日志`，
再逐个 boot 对照"上电次数 → 预期的 slot/bootcount"。

#### 3.5.4 U-Boot env 持久化验证

```bash
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/test-env.sh
```

**期望**：

```
Saving Environment to FAT... OK        ← 第一次启动里 saveenv 成功
...
UBOOT.ENV  131072  uboot.env          ← FAT 里出现 env 文件（mdir 看到）
...
Loading Environment from FAT... OK    ← 重启后读回
[boot.scr] persisted env var: testvar=hello_uboot_persist
```

**判读**：三件事都成立才算通过——saveenv 输出 OK、FAT 出现 uboot.env、重启能读回。
如果 `saveenv` 报 `Saving Environment to nowhere... not possible`，检查是否禁用了 `ENV_IS_NOWHERE`。

#### 3.5.5 手工/交互测试（自己敲 U-Boot 命令）

`-nographic` 启动后，U-Boot 的 autoboot 有 2 秒倒计时，**按任意键**可停在 `=>` 提示符。
常用命令：

```
bdinfo                          # 板级信息：DRAM、内存布局、FDT 地址
part list virtio 0              # 看 GPT 分区
virtio info                     # 看 virtio 块设备
fatload virtio 0:1 0x88000000 slot_a.itb    # 手动加载 FIT
md 0x88000000 0x20              # 看内存（FIT 头/DTB magic）
env print bootcmd               # 看启动命令
saveenv                         # 保存环境到 FAT
bootm 0x88000000                # 手动启动 FIT
```

注意：命令要等出现 `=>` 之后再输入；串口输入是逐字符的。

#### 3.5.6 坏 FIT 场景的构造与观察

```bash
SCENARIO=corruptfit bash 02-uboot-ota/mk-ab-disk.sh
TAG=fit_hash_fallback MAX_BOOTS=1 bash 02-uboot-ota/run-ab-boot.sh
```

**期望**：`## Verifying Hash Integrity ... sha256+ FAILED`（或 bootm 报错）→
`!!! bootm failed for slot A (bad FIT/hash); trying other slot` → 槽 B 启动 → `LAB BOOT OK: slot b`。

---

### 3.6 阶段 M3：内存测试

#### 3.6.1 构建实验模块与 lab initramfs

```bash
wsl -d Ubuntu-24.04 -e bash lab/build-lab.sh
wsl -d Ubuntu-24.04 -e bash lab/mk-lab-initramfs.sh
```

**期望**：`build/lab/mods/` 下 5 个 `.ko`（buddy_demo、slab_demo、pgwalk_demo、task_walk、slub_debug_demo），
`lab-initramfs.cpio.gz` 约 3.2MB。

> lab initramfs 的 `/init` 会根据内核 cmdline 的 `lab.mode=` 自动执行对应的
> `/root/lab/run-<mode>.sh`，跑完打印 `[lab] LAB DONE: <mode>` 并 `poweroff -f` 自动退出 QEMU。

#### 3.6.2 C1 内存初始化（memblock）

```bash
LAB_MODE=meminit LAB_EXTRA="memblock=debug" \
  bash lab/run-lab.sh
```

**观察什么**（日志 `~/riscv-lab/logs/lab-meminit.log`）：

1. `memblock_reserve: [...] paging_init+...`：内核把自己、initrd、DTB 保留下来；
2. `memblock_alloc_try_nid: 16777216 bytes ... sparse_init`：vmemmap/sparse 内存；
3. `Zone ranges: DMA32 [mem 0x80000000-0x9fffffff]`：内存进入 DMA32 zone；
4. `Initmem setup node 0`；
5. `Virtual kernel memory layout`（fixmap/vmemmap/vmalloc/lowmem 的虚拟地址范围）；
6. `Memory: 464956K/524288K available`；
7. `--- /proc/iomem ---` 段：`Reserved`、`Kernel image`、`Kernel code/rodata/data/bss` 等；
8. `--- debugfs memblock ---` 段：`/sys/kernel/debug/memblock/memory` 与 `reserved` 的区段列表。

**判读**：memblock=debug 的预留日志能直接看到"谁在什么时候预留了哪段物理内存"；
`/proc/iomem` 是内核视角的最终物理布局；两者对照即可理解启动早期的内存账本。

#### 3.6.3 C2 页表 walk（Sv39/48/57）

```bash
LAB_MODE=pgwalk bash lab/run-lab.sh
```

**观察什么**：

```
pgwalk: satp=a001c00000082d37 mode=Sv57 asid=28 root_ppn=82d37
pgwalk: current ... mm=... mm->pgd=... __pa(mm->pgd)=0000000082d37000
pgwalk: user start_code va=0000000000010000 mode=Sv57(10) levels=5 root_phys=0000000082d37000
pgwalk:   L4 shift=48 idx=  0 entry=...
...
pgwalk:   L0 shift=12 idx= 16 entry=...5b
pgwalk:   => LEAF L0 phys=000000009ee71000 flags=R-XU-A-
```

**判读**：
- `mode=Sv57`：运行时使用的页表级数（5 级）；
- `__pa(mm->pgd)` 与 `root_phys` 相同：当前进程页表根就是 satp 指向的表；
- 每一级 `shift/index/entry` 对应 VA 的 9 位索引；`LEAF` 给出最终物理地址与权限；
- `flags` 依次是 R/W/X/U/G/A/D，可对照"代码段可执行不可写、数据段可写、用户页带 U"。

> 想对比 Sv39：给 QEMU 加 `-cpu rv64,sv57=off,sv48=off`（只影响 CPU 声明支持级别，
> 内核会退回 Sv39），再用 `LAB_EXTRA="-cpu ..."`？——更简单的做法是改 lab/run-lab.sh 的
> QEMU 参数或在命令里加 `-cpu rv64,sv48=off,sv57=off`，然后观察 `levels=3`。

#### 3.6.4 C3 buddy 分配器

```bash
LAB_MODE=buddy bash lab/run-lab.sh
```

**观察什么**：
1. 模块打印 `MAX_PAGE_ORDER=10`、order 0..9 的分配结果（pfn/物理地址/大小）；
2. `/proc/buddyinfo` **BEFORE/AFTER** 对比（DMA32 行，列是 order 0..10 的空闲块数）；
3. `/proc/pagetypeinfo`（按迁移类型）；
4. `kmem:mm_page_alloc` trace 输出（含 pfn/order/migratetype/gfp_flags）。

**判读**：
- order-10 空闲块减少、order-4 空闲块增加 → 大块被分裂成小块；
- 低 order 分配（0~3）大量来自 **per-CPU pageset**，不一定改变 buddyinfo —— 看 trace 才能确认；
- `migratetype=0/1` 分别代表 UNMOVABLE/MOVABLE 等链表。

#### 3.6.5 C4 SLUB / slab

```bash
LAB_MODE=slab bash lab/run-lab.sh
```

**观察什么**：
- `/proc/slabinfo` 的 BEFORE/AFTER：应出现 `lab_cache` 行（`56 56 72 56 1 ...`）；
- `/sys/kernel/slab/lab_cache/`：`object_size=64, objs_per_slab, order, objects, slabs, total_objects`；
- `rmmod` 后 `lab_cache` 行消失。

**判读**：
- `objsize=72` = 64 字节对象 + SLUB 元数据/对齐，不是错误；
- 如果 `lab_cache` 没出现，通常是 **SLUB 把同尺寸 cache 合并了**（本实验用 ctor 防止合并）。

#### 3.6.6 C5 slub_debug 红区检测

```bash
LAB_MODE=slubdebug LAB_EXTRA="slub_debug=FZ" \
  bash lab/run-lab.sh
```

**观察什么**（关键日志）：

```
[Right Redzone overwritten] ... First byte 0x41 instead of 0xcc
BUG kmalloc-32 (...): Object corrupt
Object ... @offset=...
Redzone  ff...: cc cc ...
Object   ff...: 41 41 ...
...
WARNING: ... at mm/slub.c ... object_err
[<...>] slub_debug_demo_init+0x80/0x1000 [slub_debug_demo]
FIX kmalloc-32: Restoring Right Redzone ...
FIX kmalloc-32: Object ... not freed
```

**判读**：这是**故意制造的越界**（模块把 32 字节对象写 64 字节），用来验证内核调试能力：
红区被 0x41 覆盖、内核打印对象地址/内容/调用栈并拒绝释放。不是系统故障。

---

### 3.7 阶段 M4：进程测试

```bash
LAB_MODE=proc bash lab/run-lab.sh
```

**观察什么**：

1. **task_struct 遍历**（`task_walk: [n] task=... pid=.. tgid=.. comm=.. state=.. mm=.. stack=..`）：
   - `init_task=ffffffff8160d000 pid=0`：静态 0 号任务；
   - `pid=1 init`：用户态 init，有 `mm`；
   - `pid=2 kthreadd` 及其后大量 `kworker/*`：内核线程，`mm=0000000000000000`；
   - `stack=ff20000000xxxxxx`：每个任务的内核栈（16KB）。
2. **fork/exec/wait**：
   ```
   [fork_exec] parent pid=62 ppid=58
   [fork_exec] child  pid=63 ppid=62 (after fork)
   [fork_exec] exec /bin/echo OK
   [fork_exec] parent: child 63 exited, status=0x0 (exit=0)
   ```
3. **sched tracepoint**：`sched_switch: prev_comm=... prev_pid=... prev_state=R/S ==> next_comm=... next_pid=...`；
   看 fork 后父子交替、waitpid 时 `prev_state=S`（睡眠）、被唤醒。
4. **COW**：`cow_test` 的 `smaps_rollup` 前后对比：
   - 子进程写页后自己的 `Private_Dirty/Rss` 变化；
   - 父进程 `p[0]=A` 保持不变（子进程的写不会泄漏）。

**判读**：`mm=NULL` 是判断内核线程的最直接标志；`state` 值可对照 `include/linux/sched.h`；
trace 里的 `prev_state` 能解释"为什么让出 CPU"。

---

### 3.8 测试矩阵总表

| 阶段 | 目的 | 命令（在 WSL 内执行） | 观察关键字 | 通过标准 | 证据 |
|---|---|---|---|---|---|
| 0 | 环境 | `00-env/check-env.sh` | `OK qemu/riscv64-gcc/gdb` | 无 MISS | — |
| M0-1 | M 模式 U-Boot | `02-uboot-m/run-uboot-m.sh` | `U-Boot 2025.10`、`=>` | 出现提示符 | `results/m1/m1-a2-*.log` |
| M0-2 | OpenSBI+U-Boot(S) | `03-uboot-s/run-uboot-s.sh` | `OpenSBI v1.7`、`Next Mode: S-mode`、`=>` | 链完整 | `results/m1/m1-a1-*.log` |
| M0-3 | 内核+initramfs | `05-kernel/run-kernel-initramfs.sh` | `Run /init as init process`、shell 命令输出 | 能跑 `uname`/poweroff | `results/m0/m0-kernel-*.log` |
| M1-A0 | stage0→OpenSBI→stage1 | `00-rom/run-stage0.sh` | `[stage0] hartid/DTB/FDT magic`、`SBI spec version` | 三个证据齐全 | `results/m1/m1-a0-*.log` |
| M1-GDB | 交接寄存器 | `00-rom/gdb-stage0.sh` | `pc=0x1000`→`0x80000000`→`0x80200000`→`0x80400000`，mstatus/sstatus | 各级寄存器符合预期 | `results/m1/m1-a0-gdb-transcript.log` |
| M1-A1/A2/A3 | 三种 loader | `run-uboot-s/m/spl.sh` | SPL 两段日志 / M 模式无 OpenSBI | 与变体一致 | `results/m1/m1-a[123]-*.log` |
| M1-A4 | U-Boot 加载内核 | `mk-boot-disk.sh`+`run-disk-boot.sh` | `fatload`、`Moving Image ... 0x80200000`、`Run /init` | 内核从 U-Boot 启动 | `results/m1/m1-a4-*.log` |
| M2-1 | 磁盘结构 | `mk-ab-disk.sh`+`sfdisk/mdir/debugfs` | 4 分区、FAT 三文件、ota.env | 结构正确 | `results/m2/` |
| M2-2 | 四场景 | `test-ota.sh` | `LAB BOOT OK`、`ROLLBACK`、`bootm failed`、`OTA REJECTED` | 4 场景 PASS | `results/m2/{normal,bad,rollback,fit_hash_fallback}/` |
| M2-3 | env 持久化 | `test-env.sh` | `Saving Environment to FAT... OK`、`Loading Environment from FAT... OK` | 重启读回 testvar | `results/m2/m2-env-*.log` |
| M3-C1 | memblock | `LAB_MODE=meminit` + `memblock=debug` | `memblock_reserve`、Zone ranges、`Memory:` | 有预留/布局证据 | `results/m3/lab-meminit.log` |
| M3-C2 | 页表 walk | `LAB_MODE=pgwalk` | `mode=Sv57`、`LEAF ... phys=...` | satp/各级 PTE 正确 | `results/m3/lab-pgwalk.log` |
| M3-C3 | buddy | `LAB_MODE=buddy` | `alloc_pages(order=...)`、buddyinfo 变化、trace | 分配/释放/分裂可解释 | `results/m3/lab-buddy.log` |
| M3-C4 | SLUB | `LAB_MODE=slab` | `lab_cache` 行、sysfs stats | 缓存独立可查 | `results/m3/lab-slab.log` |
| M3-C5 | slub_debug | `LAB_MODE=slubdebug`+`slub_debug=FZ` | `Redzone overwritten`、`BUG kmalloc-32` | 检出越界 | `results/m3/lab-slubdebug.log` |
| M4 | 进程 | `LAB_MODE=proc` | task_walk、fork_exec、sched_switch、COW smaps | 四项证据齐全 | `results/m4/lab-proc.log` |

---

### 3.9 常见故障与排查

| 现象 | 可能原因 | 排查 |
|---|---|---|
| 交互式终端里跑脚本，QEMU 没有任何输出、日志 0 字节 | QEMU 的 stdin 是 TTY 而 stdout 是管道（tee），`-nographic` 的 stdio 串口不输出 | 仓库脚本已给 QEMU 加 `< /dev/null`；手工拼命令时自行加；或先 `bash 脚本 < /dev/null` |
| QEMU 无任何串口输出 | 没加 `-nographic`；cmdline 没写 `console=ttyS0 earlycon`；QEMU 参数顺序错 | 检查命令；先跑 `run-uboot-s.sh` 确认串口通路 |
| U-Boot 起不来 / 卡住 | 用错变体：M 模式二进制配了 `-kernel`，或 S 模式二进制没有 OpenSBI | 看 `2.3` 的组合表，M 模式用 `-bios`，S 模式用 `-bios fw_* -kernel u-boot.bin` |
| 内核无输出、卡在 `Starting kernel` | 内核没在 0x80200000；DTB 无效；RAM 太小 | GDB 停在 0x80200000 看 a0/a1；用 `-m 512M` |
| `Wrong Ramdisk Image Format` | initramfs 没包成 uInitrd | `mkimage -A riscv -O linux -T ramdisk -C gzip` 后再加载 |
| `Failed to reserve memory for fdt` | `fdt_high=~0` | boot.scr 里 `setenv fdt_high`（unset） |
| `bootm` 报 hash FAILED | FIT 被改坏/下载不完整 | 重新 mkimage；或者用该场景验证自动换槽 |
| `saveenv` 报 `Saving Environment to nowhere` | 同时启用了 `ENV_IS_NOWHERE` | 配置片段里 `# CONFIG_ENV_IS_NOWHERE is not set` 后重编 U-Boot |
| `ext4write` 报 `Unsupported RO compat features` | data 分区带 metadata_csum | 用 `mke2fs -O ^metadata_csum,^metadata_csum_seed,^64bit,^orphan_file` |
| `insmod: ... invalid module format` | 内核 release/vermagic 不匹配；用的不是同一份 build 树 | 确认 `include/config/kernel.release` 与 `uname -r` 一致；重新 `build-lab.sh` |
| GDB `target remote` 连不上 | 端口被占用；QEMU 没加 `-S -s` | `ss -ltnp | grep 1234`；确认 QEMU 参数 |
| WSL 下编译很慢 | 源码/构建放在 /mnt/d（9p） | 构建根保持在 WSL 的 `~/riscv-lab`（ext4） |
| QEMU 不退出 | 没加 `-no-reboot`；guest 没执行 poweroff | run 脚本已加 `timeout`+`-no-reboot`；交互时 Ctrl-A X |

---

## 4. 自测清单

完成下面每一项即说明你真正掌握了本实验（按顺序打勾）：

- [ ] 能说出 RISC-V 的 M/S/U 三级特权、`mret`/`sret` 的作用；
- [ ] 能解释 `a0=hartid, a1=DTB` 的交接约定，并在 GDB 里看到它；
- [ ] 能从 OpenSBI 日志指出 `Firmware Base`、`Next Address`、`Next Mode` 的含义；
- [ ] 能画/说出五级启动链及每一级可替换的方案；
- [ ] 能解释 Linux Image 头的 `text_offset` 为什么让 `booti` 把内核搬到 0x80200000；
- [ ] 能独立跑通 M0 的三条命令并解释 `Run /init` 之前内核做了什么；
- [ ] 能跑通 M1 的 stage0 链并用 GDB 单步复位向量；
- [ ] 能构建 A/B 盘，用 `sfdisk/mdir/debugfs` 检查其结构；
- [ ] 能跑四个 OTA 场景并解释 bootcount 如何触发回退；
- [ ] 能验证 U-Boot env 持久化到 FAT；
- [ ] 能解释 memblock/buddy/SLUB 三层关系，并从 `/proc/iomem`、`/proc/buddyinfo`、`/proc/slabinfo` 找证据；
- [ ] 能解释 buddyinfo 低 order 不变化的原因（pcp）；
- [ ] 能手算一个 VA 在 Sv57 下的 5 级索引（可选，用模块输出对照）；
- [ ] 能说明 `mm=NULL` 意味着什么（内核线程）；
- [ ] 能从 `sched_switch` 日志读出"谁把 CPU 让给了谁、为什么"；
- [ ] 能用 smaps_rollup 解释 COW 发生时页属性的变化。

---

## 5. 最短复现路径

```powershell
# ① 环境（一次）
wsl -d Ubuntu-24.04 -u root -e bash 00-env/setup-wsl.sh
wsl -d Ubuntu-24.04 -e bash scripts/fetch-sources.sh
wsl -d Ubuntu-24.04 -e bash 00-env/build-busybox.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/build-kernel.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/06-init/mk-initramfs.sh

# ② 基线（M0）
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh

# ③ 启动链（M1）
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/build-rom.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/run-stage0.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/gdb-stage0.sh

# ④ 分区/OTA（M2）
wsl -d Ubuntu-24.04 -e bash -lc "COMPRESSION=none bash 02-uboot-ota/test-ota.sh"
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/test-env.sh

# ⑤ 内存/进程（M3/M4）
wsl -d Ubuntu-24.04 -e bash lab/build-lab.sh
wsl -d Ubuntu-24.04 -e bash lab/mk-lab-initramfs.sh
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=meminit LAB_EXTRA="memblock=debug" bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=pgwalk bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=buddy  bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=slab   bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=proc   bash lab/run-lab.sh'
```

---

## 6. 进一步深入的建议

1. **补真实 BootROM 概念**：把 stage0 改成"从模拟 SPI Flash（pflash）读 stage1"——QEMU 支持 `-drive if=pflash`，可对照真实 SoC 的 ROM→Flash 启动。
2. **中断**：给 lab 加一个定时器中断模块（`riscv_timer` / SBI TIME），观察 PLIC/CLINT 与 `stvec`，把"黑盒"变白盒。
3. **OTA 安全**：给 FIT 加签名（`mkimage -F` + U-Boot `fit_check_sign`），或者用 `dm-verity` 保护 rootfs。
4. **内存高级主题**：加 `CONFIG_PAGE_OWNER` 看 page owner；用 `kmemleak` 找泄漏；写一个模块制造碎片并观察 `compact_memory`。
5. **进程高级主题**：用 `cgroup`/`namespaces`（需要内核配置）观察隔离；用 `perf sched`（需要 rootfs 带 perf）做调度时序图。
6. **换 SoC 模型**：QEMU 还有 `sifive_u` 等机器模型，可对照不同的固件/loader 组合（OpenSBI 平台差异）。

---

*文档版本：2026-11-12，与仓库中的脚本/日志同步。若你修改了实验脚本，本文的"期望输出"可能需要相应更新。*

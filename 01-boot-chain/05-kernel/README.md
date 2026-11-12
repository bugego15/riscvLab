# 01-boot-chain/05-kernel — 第四阶段：内核加载协议

本目录对应五阶段启动链的**第四阶段**：loader 与 Linux 内核之间的镜像格式/放置地址/寄存器约定。
它不是一个"独立代码阶段"，而是一份 ABI；实现者可以是 U-Boot `booti`、U-Boot `bootm`（FIT）
或 QEMU `-kernel`。本仓库用三种路径都验证过。

## 协议三要素（本实验实测）

| 要素 | 约定 | 实测值 |
|---|---|---|
| 镜像格式 | 64 字节 `Image` 头（`text_offset`、`image_size`、magic…） | 见下表 |
| 放置地址 | `RAM 基址 + text_offset` | `0x80000000 + 0x200000 = 0x80200000` |
| 寄存器/模式 | `a0 = hartid`、`a1 = DTB`；S 模式；MMU 关闭 | GDB：`a0=0, a1=0x82200000, sstatus=S` |

### Image 头 64 字节（Linux 6.12.117 实测）

```
code0       = 0x106f5a4d          code1      = 0x00010d60
text_offset = 0x200000   (2 MiB)
image_size  = 0x18a4000  (24.64 MiB)
flags       = 0x0                  version    = 2
magic       = 0x0000005643534952   ("RISCV\0\0\0"，已废弃)
magic2      = 0x05435352           ("RSC\x05"；ARM64 兼容位置，U-Boot 校验此字段)
res3        = 0x40                 (PE COFF 偏移)
```

U-Boot 的 `booti` 解析（`arch/riscv/lib/image.c`）：

```c
#define LINUX_RISCV_IMAGE_MAGIC 0x05435352
if (lhdr->magic != LINUX_RISCV_IMAGE_MAGIC) return -EINVAL;
*relocated_addr = gd->ram_base + lhdr->text_offset;   /* 0x80000000+0x200000 */
```

### 入口处的小把戏

Image 开头既是 PE/DOS 头又能直接执行：

```asm
0x80200000: 5a4d        c.li s4, -13      # 字节 4d 5a = "MZ"
0x80200002: 0d60106f    j    0x802010d8   # 跳过 64B 头，进入 _start_kernel
```

vmlinux 符号对照：`_start = 0xffffffff80000000`（Image 基址）、
`_start_kernel = 0xffffffff800010d8`（JAL 目标）。

## 文件说明

| 文件 | 作用 |
|---|---|
| `build-kernel.sh` | 构建 Linux 6.12.117（`defconfig` + 实验选项），产出 `Image`/`vmlinux` |
| `run-kernel-initramfs.sh` | OpenSBI fw_jump + Image + initramfs 启动，自动执行命令后关机 |
| `gdb-kernel-entry.sh` | GDB 观察内核入口：`a0=hartid、a1=DTB`、S 模式、首批指令、关键符号 |

## 前置依赖

```bash
bash scripts/fetch-opensbi.sh
bash scripts/fetch-sources.sh          # Linux 6.12.117 + U-Boot
bash 00-env/build-busybox.sh           # initramfs 需要 BusyBox
bash 01-boot-chain/06-init/mk-initramfs.sh
bash 01-boot-chain/05-kernel/build-kernel.sh   # 首次编译较慢
```

## 快速开始

```bash
# 运行内核 + initramfs（约 90 秒，自动执行命令并关机）
bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh

# GDB 观察内核入口
bash 01-boot-chain/05-kernel/gdb-kernel-entry.sh
```

### 预期输出（关键行）

```
Moving Image from 0x84000000 to 0x80200000, end=0x81aa4000
Starting kernel ...
[    0.000000] Kernel command line: console=ttyS0 earlycon keep_bootcon
[    1.431584] Run /init as init process
  RISC-V initramfs: userspace init (/init) 已运行
```

### GDB 预期（`gdb-kernel-entry.sh`）

```
[3] Linux kernel entry @0x80200000
pc      = 0x80200000
a0      = 0x0            ← hartid
a1      = 0x82200000     ← DTB（fw_jump 搬迁后的地址）
sstatus = S 模式
_start        = 0xffffffff80000000
_start_kernel = 0xffffffff800010d8
start_kernel  = 0xffffffff80c00862
```

## 三条加载路径对比

| 路径 | 解析方 | 内核放到哪 | 备注 |
|---|---|---|---|
| U-Boot `booti` | U-Boot | `ram_base + text_offset`（从 0x84000000 搬） | 磁盘启动实验（`02-uboot-ota/mk-boot-disk.sh`） |
| U-Boot `bootm`（FIT） | U-Boot | FIT 的 `load=0x80200000` | A/B OTA 的 `slot_?.itb`（带 sha256 校验） |
| QEMU `-kernel` | QEMU | 0x80200000 | 本目录 run/gdb 脚本使用 |

## 与相邻阶段的边界

- 第三阶段（U-Boot）负责"把内核加载到正确位置并准备参数"；
- 第四阶段是"加载协议本身"（Image 头/放置/寄存器/模式）；
- `Starting kernel ...` 之后是第五阶段：内核初始化 → 用户态 `/init`。

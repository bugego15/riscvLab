# 01-boot-chain/03-uboot-s — 第三阶段：二级 loader（U-Boot，S 模式）

本目录对应五阶段启动链的**第三阶段**：由 M 模式固件（OpenSBI）交接后，在 **S 模式**运行的
二级 loader。本实验使用 **U-Boot v2025.10**（`qemu-riscv64_smode_defconfig` + 实验配置片段）。

## 启动链位置

```
QEMU 复位向量(0x1000, M)
  → 第一阶段 stage0 (M, 0x80000000)        ../00-rom
  → 第二阶段 OpenSBI (M, 0x80000000)       ../01-opensbi
  → 第三阶段 U-Boot (S, 0x80200000)        ← 本目录
  → 第四阶段：U-Boot 加载内核（booti/FIT）并跳转（见 ../02-uboot-ota、../05-kernel）
```

U-Boot 从 OpenSBI 拿到 `a0=hartid, a1=DTB`，在 S 模式完成：接管参数 → 自身重定位 →
驱动模型/存储/环境变量初始化 → 执行 bootcmd/boot.scr → 加载内核 → 按内核协议跳转。

## 文件说明

| 文件 | 作用 |
|---|---|
| `build-uboot-s.sh` | 源码构建 S 模式 U-Boot（叠加 `02-uboot-ota/uboot-fragment.config`），产出 `u-boot-s.bin/.elf` |
| `run-uboot-s.sh` | 运行 `OpenSBI fw_dynamic + U-Boot(S)`，抓串口日志 |
| `gdb-uboot-s.sh` | GDB 观察 OpenSBI（M）→ U-Boot（S）交接入口 |
| `gdb-reloc.sh` | GDB 观察 U-Boot 入口 → `board_init_f` → `relocate_code` → 重定位后的 `board_init_r` |

## 前置依赖

```bash
# 工具链/模拟器（Ubuntu/WSL2）
sudo apt update
sudo apt install -y qemu-system-misc gcc-riscv64-linux-gnu gdb-multiarch make git \
  bc flex bison libssl-dev libelf-dev swig python3-dev \
  u-boot-tools mtools e2fsprogs util-linux curl

# 源码
bash scripts/fetch-opensbi.sh    # OpenSBI v1.7（gitee 镜像）
bash scripts/fetch-sources.sh    # Linux 6.12.117 + U-Boot v2025.10（kernel.org / source.denx.de）

# 先构建第二阶段（OpenSBI）
bash 01-boot-chain/01-opensbi/build-opensbi.sh
```

## 快速开始

```bash
# 构建 U-Boot S 模式
bash 01-boot-chain/03-uboot-s/build-uboot-s.sh

# 运行 OpenSBI + U-Boot(S)
bash 01-boot-chain/03-uboot-s/run-uboot-s.sh

# GDB 观察交接入口
bash 01-boot-chain/03-uboot-s/gdb-uboot-s.sh

# GDB 观察 U-Boot 重定位
bash 01-boot-chain/03-uboot-s/gdb-reloc.sh
```

### 预期输出（U-Boot 启动关键行）

```
U-Boot 2025.10
Model: riscv-virtio,qemu
DRAM:  512 MiB
Core:  27 devices, 14 uclasses, devicetree: board
Flash: 32 MiB
Hit any key to stop autoboot: 2 1 0
```

无磁盘时 autoboot 会因找不到启动介质而停在命令行；挂上磁盘后由 `../02-uboot-ota` 的
boot.scr 加载内核。

## GDB 实测：U-Boot 的接管与重定位

`gdb-reloc.sh` 依次停在：

| 观察点 | 实测值 | 含义 |
|---|---|---|
| ① U-Boot 入口 0x80200000 | `a0=hartid(0), a1=DTB(0x9fe00000)`；`mv tp,a0`、`mv s1,a1`、`csrw stvec` | S 模式接管，保存 hartid/DTB、设异常入口 |
| ② `board_init_f`（链接地址 0x80218a7c） | `gp=0x801f7e90`（gd）；`gd->relocaddr=0`（尚未计算） | 重定位前初始化：FDT 解析、早期 malloc、计算搬移目标 |
| ③ `relocate_code`（0x802000a2） | `gd->relocaddr=0x9f6ce000`；随后 `copy_loop` 拷贝、`stack_setup`、`clear_bss` | 把自身搬到 RAM 高地址 |
| ④ 重定位后的 `board_init_r` | PC=`0x9f6e7040` = `0x9f6ce000+0x19040` | 已在高地址运行，重定位完成 |

对照 `bdinfo`：`relocaddr=0x9f6ce000`、`reloc off=0x1f4ce000`。

**注意**：脚本已把 QEMU 的 stdin 重定向为 `/dev/null`（交互终端下 QEMU `-nographic`
可能因 stdin 是 TTY、stdout 是管道而不输出）。

## 与相邻阶段的边界

- 第二阶段（OpenSBI）负责 M 模式初始化与 `mret` 到 S；**第三阶段只跑在 S 模式**；
- 第三阶段负责"找到并加载内核"；**"内核加载协议本身"（Image 头/booti/FIT）属于第四阶段**；
- U-Boot 的 `booti`/`bootm` 是第四阶段协议的实现者，`../02-uboot-ota` 演示了完整的加载+启动过程。

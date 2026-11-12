# RISC-V 启动流程：从复位向量到应用层 init

实验平台：QEMU `-M virt`（RISC-V 64）。对应日志在 `results/m0/`、`results/m1/`。

## 1. 全链条一图

```
QEMU reset
   │  PC = 0x1000（QEMU 内置 ROM，硬件复位向量的替身）
   ▼
[ROM code]  csrr a0,mhartid ; ld a1,32(t0) ; ld t0,24(t0) ; jr t0
   │  a0 = hartid(0)  a1 = DTB(0x9fe00000)   → 跳到 0x80000000
   ▼
[选择点 1] 0x80000000 第一段代码
   ├─ (a) QEMU 直接把 -bios 固件放到这里（本实验 M0/A1 默认）
   └─ (b) 自写 stage0（本实验 A0，模拟 BootROM 的打印/校验/传参职责）
   ▼
[选择点 2] 0x80000000/0x80200000 M 模式固件（SBI 提供者）
   ├─ OpenSBI fw_jump / fw_dynamic（M0/A1/A4）
   └─ U-Boot 直接跑 M 模式、自身作固件（A2）
   ▼
[选择点 3] 二级 loader（S 模式）
   ├─ U-Boot proper（A1/A4，地址 0x80200000 起）
   └─ U-Boot SPL 两段式：SPL(M) → u-boot.itb = OpenSBI + U-Boot proper（A3）
   ▼
[选择点 4] 内核加载协议
   ├─ QEMU -kernel 直接加载（M0）
   ├─ U-Boot booti：从 virtio-blk FAT 分区 fatload Image/uInitrd（A4）
   └─ U-Boot bootm：FIT（kernel+dtb+ramdisk+hash 校验，M2 的 A/B 槽）
   ▼
[选择点 5] Linux 用户态起点
   ├─ initramfs 中的 /init（M0/A4）
   └─ rootfs 分区上的 BusyBox init（inittab → rcS → shell，M2）
   ▼
应用层初始化完成
```

## 2. 五个选择点与实测结论

| # | 选择点 | 实验 | 关键结论 |
|---|---|---|---|
| 1 | 复位后第一段代码 | A0、M0 | QEMU `virt` 没有真实芯片 BootROM：ROM 区 0x1000 的代码只做三件事——取 mhartid → a0、取 DTB 指针 → a1、跳到固件加载地址（默认 0x80000000）。真实芯片的 BootROM 还要做 DDR 初始化、从 SPI Flash 读一级镜像，这部分用自写 stage0 模拟并对比说明。 |
| 2 | M 模式固件 | A1、A2 | M0/A1 中 OpenSBI 在 M 模式，U-Boot 在 S 模式，SBI ecall 由 OpenSBI 处理（A0 的 stage1 实测 `ecall` 可打印、可读 SBI 版本 0x03000000）。A2 中无 OpenSBI，U-Boot 自己跑 M 模式作固件。 |
| 3 | 二级 loader | A1、A3 | U-Boot proper 由上一级放到 0x80200000 并进入 S 模式。A3 的 SPL 两段式：`-bios spl/u-boot-spl.bin -device loader,file=u-boot.itb,addr=0x80200000`，串口同时出现 `U-Boot SPL` 与 `U-Boot` 两段输出，说明 SPL 先运行、再加载含 OpenSBI 与 proper 的 FIT。 |
| 4 | 内核加载协议 | M0、A4 | M0 由 QEMU 直接 `-kernel Image`；A4 由 U-Boot：boot.scr → `fatload virtio 0:1` 读 Image 与 uInitrd → `booti`，日志显示 `Moving Image from 0x84000000 to 0x80200000`（booti 按 Image 头 text_offset=0x200000 重定位），随后 `Run /init as init process`。 |
| 5 | 用户态起点 | M0、A4、M2 | 内核 `kernel_init` 执行 `/init`（initramfs）或 rootfs 的 `/sbin/init`。BusyBox init 的链路：`/sbin/init` → `/etc/inittab` → `rcS` 脚本 → shell/getty，是“应用层初始化”的最小可控模型。 |

## 3. 实测：复位向量与逐级交接（GDB 证据）

`results/m1/m1-a0-gdb-transcript.log`（自写 stage0 链）与 `m1-a1-gdb-transcript.log`（OpenSBI+U-Boot）记录了完整过程：

**① 复位时（PC=0x1000，M 模式，a0=a1=0）：**
```
=> 0x1000: auipc t0,0x0
   0x1004: addi  a2,t0,40      # a2 = 0x1028（dynamic info 地址，QEMU 专用）
   0x1008: csrr  a0,mhartid
   0x100c: ld    a1,32(t0)     # a1 = DTB
   0x1010: ld    t0,24(t0)     # t0 = 固件入口
   0x1014: jr    t0
```
单步 6 条后：`pc=0x80000000, a0=0(hartid), a1=0x9fe00000(DTB)`。

**② stage0 入口（M 模式，0x80000000）：** `sp=0, a0=0, a1=0x9fe00000`。
自写 stage0 打印并校验 FDT magic（小端读出 0xedfe0dd0 = 大端 0xd00dfeed）。

**③ OpenSBI 入口（M 模式，0x80200000）：** `sp=0x80004730, a0=0, a1=0x9fe00000, mstatus=0xa00000000`。
OpenSBI 的第一批指令是保存 a0/a1/a2 后进入 C 初始化。

**④ S 模式 payload / U-Boot 入口（0x80400000 / 0x80200000）：**
`sstatus=0x8000000200006000`（S 模式），a1 已被 OpenSBI 换成它整理后的 DTB（0x80400000 链中为 0x82400000）。

**⑤ Linux 内核入口（S 模式，0x80200000）：** `pc=0x80200000, a0=0(hartid), a1=0x82200000(DTB)`。
QEMU 直接 `-kernel` 启动时，fw_jump 把 DTB 从 0x9fe00000 搬到 0x82200000 再传给内核（与 OpenSBI 启动日志 `Domain0 Next Arg1: 0x82200000` 一致）。
内核符号（vmlinux）：`start_kernel=0xffffffff80c0086a`、`setup_arch=0xffffffff80c04676`、`paging_init=0xffffffff80c07528`、`mm_init=0xffffffff80013c6c`。

## 4. 地址与特权级布局（QEMU virt，512MB RAM）

| 地址 | 内容 | 特权级 |
|---|---|---|
| 0x1000 | QEMU 内置复位向量 ROM | M |
| 0x80000000 | 固件（OpenSBI / U-Boot M）或自写 stage0 | M |
| 0x80200000 | U-Boot proper（S 模式）或 Linux Image 入口 | S |
| 0x80400000 | A0 实验中的 S 模式 payload（自定义 OpenSBI fw_jump 跳转地址） | S |
| 0x9fe00000 | QEMU 生成的 DTB（512MB RAM 高址） | - |
| 0x82200000 | OpenSBI 整理后传给内核的 DTB | - |

交接协议（RISC-V 约定）：**a0 = hartid，a1 = DTB 地址**。M→S 的切换由固件设置 `mstatus.MPP` 后 `mret`，S 模式代码看到的是 `sstatus`。

## 5. 每种启动方式的对比与适用场景

| 组合 | 组成 | 优点 | 缺点/说明 |
|---|---|---|---|
| M 模式 U-Boot 直接作固件 | U-Boot（M） | 链最短 | 无 SBI 提供者；U-Boot 需自己承担 M 模式职责，现代 RISC-V 不推荐 |
| OpenSBI + S 模式 U-Boot | OpenSBI + U-Boot proper | 标准做法，SBI 稳定、升级解耦 | 需要单独维护 OpenSBI |
| OpenSBI fw_dynamic | QEMU 传 dynamic info | 支持下一级动态信息（hartid/DTB/next stage） | 与 QEMU 特性耦合，固件需支持 dynamic |
| U-Boot SPL 两段式 | SPL(M) + OpenSBI+PBR FIT | 贴近真实 SoC（ROM→SPL→U-Boot） | QEMU 上用 `-device loader` 模拟 SPL 后续镜像加载 |
| QEMU 直接 `-kernel` | OpenSBI + QEMU loader | 最快，适合内核开发 | 绕过了 U-Boot，不能验证分区/OTA 流程 |

## 6. 与真实 SoC 的差异（学习时的对照点）

- QEMU `virt` 的“BootROM”只是复位向量桩：**不做 DDR 初始化、不做 Flash 读取**。真实芯片（如 StarFive JH7110、Allwinner D1）的 BootROM 从 SPI Flash/eMMC 读 SPL，再校验、跳转。
- QEMU 上 `-device loader` 等价于真实 ROM/SPL 的“加载下一级到 SRAM/DRAM”，SPL 在 QEMU 上靠这个机制拿到 u-boot.itb；真实 SoC 则由 SPL 自己去读 Flash。
- 真实产品常用 eMMC/SPI NOR + GPT/MBR 分区；QEMU 用 virtio-blk 模拟块设备，分区表/文件系统/U-Boot 命令完全一致，OTA 流程可直接复用。
- 中断控制器（PLIC/CLINT）在 QEMU 中完整存在，但本实验不研究其中断细节；内核依赖 timer 中断运行，但作为黑盒。

## 7. 应用层 init 实测（M2 的 rootfs 启动）

M2 的 A/B rootfs 把「应用层初始化」完整跑了一遍（BusyBox init）：

```
内核 kernel_init → /sbin/init（busybox init）
  → /etc/inittab
  → ::sysinit:/etc/init.d/rcS
      ├─ mount proc / sys / devtmpfs
      ├─ mount data 分区 /dev/vda4 → /data
      ├─ 如有 OTA 包标记 → 执行 /usr/sbin/ota-agent.sh（校验、写非活动槽、置待升级、reboot）
      ├─ 写 /data/ota.env 确认当前槽（slot=X, upgrade=0, bootcount=0）
      └─ echo "LAB BOOT OK: slot X"
  → ::askfirst:/bin/sh（控制台 shell）
```

日志证据：`results/m2/normal/boot2.log`（`LAB BOOT OK: slot b`）、`results/m2/rollback/boot5.log`（回退后 `LAB BOOT OK: slot a`）。

## 8. 可复现命令

```powershell
# M0 基线
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh

# M1-A0 自写 stage0
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/build-rom.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/run-stage0.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/gdb-stage0.sh

# M1-A1/A2/A3
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/01-opensbi/build-opensbi.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/build-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/build-uboot-m.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/04-spl/build-uboot-spl.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/run-uboot-m.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/04-spl/run-spl.sh

# M1-A4 U-Boot 从 virtio-blk FAT 启动内核
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/mk-boot-disk.sh
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/run-disk-boot.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/gdb-kernel-entry.sh
```

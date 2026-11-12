# 总结报告：RISC-V 启动流程与内核内存/进程实验

> 目标：只用 QEMU（`-M virt`），把「启动流程」和「内存/进程」两条主线跑通并留下可复现证据。
> 结论：**全部达成**。M0–M4 实验完成，`docs/01`–`04` 四份学习文档 + 原始日志 + 一键脚本已交付。

## 1. 需求对照

| 你的需求 | 完成情况 | 证据/文档 |
|---|---|---|
| 1. BootROM/loader/SPL/U-Boot/kernel/应用层 init 的启动流程与选择 | ✅ 五级选择点逐项实测（QEMU 复位向量、自写 stage0、OpenSBI、U-Boot M/S/SPL、booti/FIT、BusyBox init） | `docs/01-boot-flow.md`、`results/m0`、`results/m1` |
| 2. U-Boot 分区、OTA 升级 | ✅ 256MB GPT 盘、A/B 双槽、FIT 哈希校验、env 落盘、bootcount 自动回退、用户态 OTA agent；4 个场景通过 | `docs/02-uboot-ota.md`、`results/m2` |
| 3. Linux 内存初始化、内存分配管理 | ✅ memblock 启动日志、Sv57 5 级页表 walk、buddy（含 pcp 现象）、SLUB/slab、slub_debug 红区检测 | `docs/03-memory.md`、`results/m3` |
| 4. 进程管理 | ✅ task_struct 链表（PID1/kthreadd/内核线程）、fork/exec/wait、sched tracepoint、COW smaps 验证 | `docs/04-process.md`、`results/m4` |
| 不关心外设/时序、中断、虚拟化 | ✅ 只把 UART 控制台、virtio-blk、sifive_test 当基础设施；未做中断/虚拟化专题 | — |
| 不在乎系统怎么构建 | ✅ 全部手搓：OpenSBI/U-Boot/BusyBox 源码构建，BusyBox rootfs；未用 Yocto/Buildroot | — |

## 2. 系统总览

| 组件 | 版本/来源 |
|---|---|
| 仿真器 | QEMU 8.2.2（WSL）+ Windows QEMU 11.1 交叉验证 |
| 固件 | OpenSBI 1.7（源码，gitee 镜像） |
| 引导 | U-Boot 2025.10（源码，source.denx.de）——M 模式 / S 模式 / SPL 三种变体 |
| 内核 | Linux 6.12.117（kernel.org），riscv defconfig + debug/ftrace/debugfs |
| 用户态 | BusyBox 1.37.0 静态（initramfs 与 ext4 rootfs A/B） |
| 工具链 | riscv64-linux-gnu-gcc 13.3.0、gdb-multiarch 15.1 |
| 构建位置 | WSL Ubuntu 24.04：`~/riscv-lab`（源码/构建产物/日志）；代码与文档在本仓库 |

通用 QEMU 模板：

```bash
qemu-system-riscv64 -M virt -m 512M -nographic -no-reboot \
  -bios <fw>.bin -kernel <u-boot|Image> \
  [-initrd initramfs.cpio.gz] [-append "console=ttyS0 earlycmd..."] \
  [-drive file=disk.img,format=raw,if=none,id=hd0 -device virtio-blk-device,drive=hd0]
```

## 3. 三张主线图

### 3.1 启动链（M0/M1）

```
QEMU reset @0x1000（内置 ROM 桩）
   │ csrr a0,mhartid ; ld a1,DTB ; ld t0,entry ; jr t0
   ▼
[选择点1] 0x80000000：QEMU 直接放 -bios 固件 / 自写 stage0（A0 实验）
   ▼
[选择点2] M 模式固件：OpenSBI fw_jump/fw_dynamic（M0/A1/A4）或 U-Boot M 模式（A2）
   ▼
[选择点3] 二级 loader：U-Boot proper(S, 0x80200000)（A1）或 SPL→u-boot.itb 两段式（A3）
   ▼
[选择点4] 内核加载：QEMU -kernel（M0）/ U-Boot booti（A4）/ U-Boot bootm FIT + sha256（M2）
   ▼
[选择点5] 用户态 init：initramfs /init（M0/A4）或 rootfs /sbin/init → BusyBox inittab → rcS（M2）
```

GDB 实测关键点（`results/m1/*gdb*`）：
- 复位 ROM 指令序列与 6 步跳到 0x80000000：`a0=0(hartid), a1=0x9fe00000(DTB)`；
- OpenSBI 入口 M 模式（`mstatus`），U-Boot/内核入口 S 模式（`sstatus`），地址 0x80200000；
- 内核符号：`start_kernel=0xffffffff80c0086a` 等。

### 3.2 内存管理（M3）

```
物理内存 (QEMU virt: 0x80000000..0x9fffffff, 512MB)
   │ 启动早期
   ▼
memblock（memory / reserved 两类区域）
   │ paging_init：Sv57 5 级页表 + 直接映射
   │ mm_init/free_area_init：按 zone(DMA32) 初始化 buddy
   ▼
buddy（order 0..10 的 2^n 连续页；/proc/buddyinfo, /proc/pagetypeinfo, kmem tracepoints）
   │ 小块内核对象
   ▼
SLUB（per-cache slab：lab_cache/kmalloc-*；/proc/slabinfo, /sys/kernel/slab/*；slub_debug=FZ 红区检测）
```

实测：`satp` 为 Sv57、根页表物理地址 = `__pa(mm->pgd)`；用户/内核/直接映射 VA 的 5 级 PTE 及权限位全部解出（`results/m3/lab-pgwalk.log`）。

### 3.3 进程生命周期（M4）

```
init_task(pid 0, static)
 ├─ PID 1 init ──(fork)── child → exec → wait/wakeup
 └─ PID 2 kthreadd ── kernel threads (mm=NULL, 借用 active_mm)
      调度：sched_switch / sched_wakeup tracepoint
      地址空间：fork 共享页表项(COW) → 写触发 page fault → 复制页 → 映射可写
```

## 4. 里程碑与产出

| 里程碑 | 状态 | 关键产物 |
|---|---|---|
| M0 环境+基线 | ✅ | `results/m0`：U-Boot M/S 启动日志、Linux→initramfs shell 日志、Windows QEMU 交叉验证 |
| M1 启动链五级对照 | ✅ | `docs/01-boot-flow.md`、`results/m1`、自写 stage0/stage1、GDB transcript、三种 U-Boot 变体 |
| M2 分区+A/B OTA | ✅ | `docs/02-uboot-ota.md`、`results/m2`（4 场景 × 逐次上电日志 + 最终 ota.env + env 持久化） |
| M3 内存 | ✅ | `docs/03-memory.md`、`results/m3`（meminit/pgwalk/buddy/slab/slubdebug 5 份日志） |
| M4 进程 | ✅ | `docs/04-process.md`、`results/m4`（task_walk/fork-exec/sched trace/COW） |
| M5 汇总 | ✅ | 本文件 + README/PLAN 收尾 |

## 5. 一键复现

```powershell
# 0) 一次性环境（root 安装 apt 包 + 下载源码 + 构建 busybox/内核）
wsl -d Ubuntu-24.04 -u root -e bash 00-env/setup-wsl.sh
wsl -d Ubuntu-24.04 -e bash scripts/fetch-sources.sh
wsl -d Ubuntu-24.04 -e bash 00-env/build-busybox.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/build-kernel.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/06-init/mk-initramfs.sh

# 1) M0 基线
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/run-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh

# 2) M1 启动链
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/01-opensbi/build-opensbi.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/02-uboot-m/build-uboot-m.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/03-uboot-s/build-uboot-s.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/04-spl/build-uboot-spl.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/build-rom.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/run-stage0.sh
wsl -d Ubuntu-24.04 -e bash 01-boot-chain/00-rom/gdb-stage0.sh
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/mk-boot-disk.sh
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/run-disk-boot.sh

# 3) M2 A/B OTA（4 场景 + env 持久化）
wsl -d Ubuntu-24.04 -e bash -lc "COMPRESSION=none bash 02-uboot-ota/test-ota.sh"
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/test-env.sh

# 4) M3 内存 + M4 进程
wsl -d Ubuntu-24.04 -e bash lab/build-lab.sh
wsl -d Ubuntu-24.04 -e bash lab/mk-lab-initramfs.sh
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=meminit LAB_EXTRA="memblock=debug" bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=pgwalk  bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=buddy   bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=slab    bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=slubdebug LAB_EXTRA="slub_debug=FZ" bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=proc    bash lab/run-lab.sh'
```

## 6. 关键发现 / 踩坑清单

1. **QEMU virt 的“BootROM”只是复位向量桩**：0x1000 处只有取 hartid/DTB/跳转的几条指令；真实 BootROM 的 DDR 初始化/Flash 读取需要自写 stage0 对照理解。
2. **RISC-V U-Boot booti 会按 Image 头 `text_offset` 重定位内核**（`Moving Image from 0x84000000 to 0x80200000`）。
3. **FIT 内 gzip 内核在本 QEMU/U-Boot 组合下会启动挂起**（U-Boot 虽有 GZIP/ZLIB），改用未压缩 FIT；哈希校验/槽机制不受影响。
4. **U-Boot `fdt_high/~0` 默认值**会让 booti 传自己的控制 FDT 导致 `Failed to reserve memory for fdt`；boot.scr 里 unset `fdt_high/initrd_high`。
5. **U-Boot env 必须禁用 `ENV_IS_NOWHERE`**，否则 `saveenv` 报 “Saving Environment to nowhere... not possible”。
6. **U-Boot ext4write 不支持 metadata_csum/64bit/orphan_file**：data 分区必须用 `-O ^metadata_csum,^metadata_csum_seed,^64bit,^orphan_file`。
7. **boot.scr 里 env import/export 缓冲区要避开脚本自身所在地址**（否则覆盖正在执行的脚本）。
8. **buddyinfo 低 order 分配可能看不到变化**：先命中 per-CPU pageset（pcp），需要 tracepoint 佐证。
9. **SLUB 默认会合并兼容 cache**：`kmem_cache_create` 加 ctor 才能让自定义 cache 独立出现在 `/proc/slabinfo`。
10. **`slub_debug=FZ`** 能在 `kfree` 时用红区检出越界（0xcc → 被写数据），并打印对象地址与调用栈。

## 7. 与生产系统的差异（已知限制）

| 方面 | QEMU 实验 | 生产环境 |
|---|---|---|
| BootROM | 复位向量桩 / 自写替身 | 真实 ROM code：DDR init、Flash 读取、校验、掉电时序 |
| 存储 | virtio-blk | eMMC/UFS/SPI NOR + 真实控制器时序 |
| 看门狗/复位 | guest `reboot -f`、QEMU `-no-reboot` 模拟 | 硬件 WDT、PMIC、掉电保持 |
| OTA 安全 | sha256 完整性 + FIT 哈希 | 包签名、dm-verity、防回滚计数器、差分升级、A/B 双备份元数据 |
| 网络升级通道 | 未启用（包预置在 data 分区） | 下载/断点续传/重试 |
| 中断/虚拟化 | 作为黑盒（不展开 PLIC/CLINT、H 扩展） | 需按芯片平台深入 |

## 8. 交付物索引

```
riscvLab/            （本仓库）
├─ README.md
├─ 00-env/（环境检查/搭建、BusyBox 构建、版本锁定）
├─ 01-boot-chain/（五阶段启动链：00-rom/01-opensbi/02-uboot-m/03-uboot-s/04-spl/05-kernel/06-init）
├─ 02-uboot-ota/（A/B 盘、boot.scr、rootfs、OTA agent、场景测试）
├─ lab/（M3/M4 共享实验框架：mods/tests/overlay + build/mk/run 脚本）
├─ docs/
│  ├─ 00-principles-and-testing.md  原理 + 测试方法/判读（主手册）
│  ├─ 01-boot-flow.md      启动流程（五级选择点 + GDB 证据）
│  ├─ 02-uboot-ota.md      分区与 A/B OTA（四场景 + 踩坑）
│  ├─ 03-memory.md         内存初始化/页表/buddy/slab/slub_debug
│  ├─ 04-process.md        进程管理（task_struct/调度/COW）
│  └─ 05-summary.md        本文件（总报告）
└─ scripts/（common.sh、fetch-opensbi.sh、fetch-sources.sh）

# 运行产物（不在仓库）：~/riscv-lab/{src,build,images,logs}；
# 结果日志由脚本生成（部分复制到 build/results/ 或 results/）。
```

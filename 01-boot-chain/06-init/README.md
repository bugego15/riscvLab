# 01-boot-chain/06-init — 第五阶段：应用层 init（initramfs）

本目录对应五阶段启动链的**第五阶段**：内核初始化完成后，启动第一个用户态进程（PID 1），
进入应用层。本目录提供最小 BusyBox initramfs 的构建脚本。

## initramfs 里的 `/init` 做什么

`mk-initramfs.sh` 用 BusyBox 安装树 + 内联脚本生成 `initramfs.cpio.gz`，其中 `/init`：

```sh
#!/bin/busybox sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo "RISC-V initramfs: userspace init (/init) 已运行"
exec /bin/sh
```

内核启动完成后会执行 `/init`（`Run /init as init process`），`/init` 挂载伪文件系统并进入交互 shell。

## 文件说明

| 文件 | 作用 |
|---|---|
| `mk-initramfs.sh` | 用 `$TOOLS/busybox-riscv64`（或 `$BUILD_ROOT/rootfs/busybox-install`）生成 `initramfs.cpio.gz` |

## 快速开始

```bash
# 前置：00-env/build-busybox.sh
bash 01-boot-chain/06-init/mk-initramfs.sh
bash 01-boot-chain/05-kernel/run-kernel-initramfs.sh
```

### 预期输出（关键行）

```
[    0.000000] Run /init as init process
==================================================
  RISC-V initramfs: userspace init (/init) 已运行
  pid=1  cmdline: console=ttyS0 earlycon keep_bootcon
  现在可以将此 shell 交给后续实验（分区/OTA/模块）
==================================================
```

`run-kernel-initramfs.sh` 会自动在 shell 里执行 `uname -a`、`cat /proc/cmdline`、
`head -5 /proc/meminfo`、`cat /proc/iomem | head -12`，最后 `poweroff -f` 关机。

## 两种 init 形态（本实验都有）

| 形态 | 位置 | 行为 |
|---|---|---|
| **initramfs `/init`** | 本目录（`initramfs.cpio.gz`） | RAM 里的最小用户态：挂 proc/sys/dev → shell；用于启动链/内核实验 |
| **rootfs BusyBox init** | `02-uboot-ota/mk-rootfs.sh` | 磁盘 rootfs：`/etc/inittab` → `/etc/init.d/rcS` → shell；含 A/B 槽确认、OTA agent |

## 备注

- initramfs 是内核内置的早期用户态；本实验的内核用 `-initrd` 或 U-Boot `booti` 加载它；
- 真正的产品常把 initramfs 用于挂载根文件系统，再 `switch_root` 到 rootfs（本实验简化为直接进 shell）；
- 第五阶段深入内容（init 调用链、PID1 职责、fork/exec、进程管理）在后续 M4 实验中展开。

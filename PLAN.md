# 实施计划（已与用户确认）

## 已确认的决策

1. 全部构建与运行在 WSL2 Ubuntu 24.04 内完成（已把 WSL 虚拟磁盘从 F 盘迁到 E 盘）；Windows QEMU 11.1 仅做交叉验证。
2. 用户态：BusyBox initramfs 为主线；**systemd 对照已去掉**。
3. 保留：自写裸机 stage0 + GDB 单步各级入口；内核模块（buddy/slab/task 观察）。
4. 下载源避开 GitHub：内核 kernel.org、U-Boot source.denx.de、OpenSBI gitee 镜像、busybox.net、ports/cdimage.ubuntu.com。

## 里程碑

| 里程碑 | 内容 | 验收标准 |
|---|---|---|
| M0 | 环境安装；apt 版 OpenSBI+U-Boot 基线；Linux 6.12 源码构建；BusyBox initramfs 启动到 shell | 串口日志完整走通 OpenSBI→U-Boot→Kernel→shell；Windows QEMU 交叉验证 |
| M1 | 五级启动链对照实验 + `docs/01-boot-flow.md` | 每级可单独替换运行；GDB 记录各级入口寄存器；启动方式对照表 |
| M2 | U-Boot 分区 + A/B OTA + 自动回退 + `docs/02-uboot-ota.md` | env 持久化验证；正常升级/坏包拒绝/坏镜像回退三个场景日志 |
| M3 | 内存初始化 + buddy + slab + `docs/03-memory.md` | memblock 日志、页表 walk、buddyinfo 变化、slabinfo 与越界检测记录 |
| M4 | 进程管理 + `docs/04-process.md` | task 遍历、fork/exec/wait、sched tracepoint、COW 对比记录 |
| M5 | 汇总图 + 最终报告 | 启动时序图、内存布局图、进程生命周期图、总结 |

## 专题 A：启动链的 5 个选择点

| # | 选择点 | 对照方案 |
|---|---|---|
| 1 | 复位后第一段代码 | QEMU 内置复位向量 / 自写 stage0 /（进阶）pflash 模拟 Flash 启动 |
| 2 | M 模式固件 | OpenSBI fw_jump / fw_dynamic / U-Boot M 模式直接作 bios |
| 3 | 二级 loader | U-Boot proper（S 模式）/ U-Boot SPL 两段式 / 自写 loader |
| 4 | 内核加载协议 | QEMU `-kernel` 直接起 / U-Boot `booti` / FIT(`bootm`) + hash |
| 5 | 用户态起点 | initramfs 内 `/init` → inittab → rcS；A/B rootfs + switch_root |

## 风险与预案

- WSL 在机械盘上编译偏慢 → 编译后台运行，不阻塞其他实验。
- U-Boot SPL 在 QEMU 的加载方式与真机不同 → 已按官方文档用 `-device loader` 方案；若不顺，用自写 stage1 演示同等概念并注明差异。
- env 持久化到 virtio+FAT 若失败 → 备选 env 放 ext4，或 OTA 状态放 data 分区文件由 bootcmd 读取。

## 完成状态（2026-11-12）

| 里程碑 | 状态 | 备注 |
|---|---|---|
| M0 环境+基线 | ✅ 完成 | OpenSBI→U-Boot(M/S)→Linux→initramfs shell；Windows QEMU 交叉验证 |
| M1 启动链五级对照 | ✅ 完成 | 自写 stage0+GDB、OpenSBI/U-Boot M/S/SPL 源码构建、booti/FIT 加载内核 |
| M2 分区+A/B OTA | ✅ 完成 | 4 场景通过（正常/坏包/坏镜像回退/FIT hash 回退）；env 落盘 FAT 验证 |
| M3 内存 | ✅ 完成 | memblock 日志、Sv57 页表 walk、buddy、SLUB、slub_debug 红区 |
| M4 进程 | ✅ 完成 | task_walk、fork/exec/wait、sched tracepoint、COW |
| M5 汇总 | ✅ 完成 | `docs/05-summary.md` |

最终文档：`docs/01-boot-flow.md`、`02-uboot-ota.md`、`03-memory.md`、`04-process.md`、`05-summary.md`。
证据：`results/m0`–`m4`。所有脚本在 WSL 内可复现（无需 GitHub）。

# RISC-V U-Boot 分区与 A/B OTA 升级

实验平台：QEMU `-M virt`，U-Boot 2025.10（S 模式）+ virtio-blk 磁盘 + Linux 6.12 rootfs。
证据：`results/m2/`（每个场景一个子目录，含逐次上电日志与最终 `ota.env`）。

## 1. 结论

在 QEMU 上完整复现了嵌入式产品常见的 **A/B 双槽 + U-Boot 启动计数 + 失败自动回退** OTA 流程，并验证了：

- U-Boot 环境变量可以持久化在 virtio-blk 的 FAT 分区（`saveenv` / `uboot.env`，重启后读回）；
- U-Boot 从 virtio-blk 的 GPT 分区加载 FIT（内核 + DTB，sha256 校验），按槽启动不同 rootfs；
- 用户态 OTA agent 能做「校验包 → 写非活动槽 → 置待升级标记 → 重启」；
- 启动失败（坏镜像）会被 bootcount 捕获并自动回退到旧槽；
- FIT 哈希校验失败时 boot.scr 能立即换槽启动。

## 2. 磁盘分区设计（256 MiB GPT）

| 分区 | 大小 | 文件系统 | 内容 |
|---|---|---|---|
| p1 | 64 MiB | FAT16 | `boot.scr`、`slot_a.itb`、`slot_b.itb`、`uboot.env`（U-Boot 环境，saveenv 生成） |
| p2 | 48 MiB | ext4 | rootfs_a（BusyBox init，槽 A） |
| p3 | 48 MiB | ext4 | rootfs_b（BusyBox init，槽 B） |
| p4 | 32 MiB | ext4（无 metadata_csum） | `ota.env` 状态文件 + OTA 包（`rootfs_b.img.gz` + sha256 + `do-ota` 标记） |

为什么 data 分区要特殊格式化：U-Boot 的 **ext4write 不支持 metadata_csum/64bit/orphan_file**（只读没问题），否则写状态时报
`Unsupported RO compat features found 00000400, not writing.`。内核端无影响。

## 3. U-Boot 关键配置（`02-uboot-ota/uboot-fragment.config`）

| 配置 | 作用 |
|---|---|
| `CONFIG_VIRTIO/VIRTIO_MMIO/VIRTIO_BLK=y` | 识别 QEMU virtio-blk 磁盘 |
| `CONFIG_CMD_FAT/CMD_EXT4/CMD_EXT4_WRITE=y`、`CONFIG_FAT_WRITE=y` | 读写 FAT / ext4 分区 |
| `CONFIG_ENV_IS_IN_FAT=y` + `ENV_FAT_INTERFACE="virtio"` + `ENV_FAT_DEVICE_AND_PART="0:1"` | env 落盘到 p1 FAT |
| `# CONFIG_ENV_IS_NOWHERE is not set` | **关键**：否则 env_load 选中 nowhere，`saveenv` 报 “Saving Environment to nowhere... not possible” |
| `CONFIG_CMD_IMPORTENV/CMD_EXPORTENV=y` | `env import/export` 读写 `ota.env` 文本状态 |
| `CONFIG_CMD_SETEXPR=y` | `setexpr bootcount ${bootcount} + 1` |
| `CONFIG_FIT=y`、`CMD_BOOTM=y`、`CMD_SOURCE=y` | FIT 校验启动、执行 boot.scr |
| `CONFIG_BOOTCOMMAND="...fatload virtio 0:1 ${scriptaddr} boot.scr; source ${scriptaddr}"` | 加载并执行启动脚本 |
| 不启用 BOOTCOUNT 框架 | A/B 计数在 boot.scr 中手动实现并持久化到 data 分区，避免与 U-Boot 自带 bootcount 双计 |

## 4. boot.scr 状态机

```
上电
 │
 ├─ 从 data 分区 ext4load ota.env → env import -t（无则用首次启动默认值：slot=a, upgrade=0, bootcount=0, bootlimit=3）
 │
 ├─ upgrade_available == 1 ?
 │    ├─ bootcount += 1
 │    ├─ bootcount > bootlimit ? ── 是 → 切到另一个槽，upgrade_available=0, bootcount=0（ROLLBACK）
 │    └─ env export -t + ext4write 回 data 分区（掉电前持久化）
 │
 ├─ 按 slot 选择 FIT/rootfs：A→slot_a.itb+/dev/vda2；B→slot_b.itb+/dev/vda3
 ├─ fatload + bootargs "console=ttyS0 earlycon root=... rw rootwait" + bootm
 │
 └─ bootm 失败（FIT/hash 坏）→ 打印 fallback，加载另一个槽再 bootm
```

rootfs 里的 `/etc/init.d/rcS`（BusyBox init 的 sysinit）负责「应用层确认」：

- 正常启动 → 写 `ota.env`：`slot=<当前槽>; upgrade_available=0; bootcount=0`；
- 若 `/data/pkg/do-ota` 存在 → 先执行 `/usr/sbin/ota-agent.sh`；
- 若 `/etc/fail-boot` 存在（坏镜像演示）→ 打印 `LAB BOOT FAIL` 后 `reboot -f`。

用户态 OTA agent 流程：`sha256sum 校验包 → gunzip -c | dd of=/dev/vda3（写非活动槽）→ 写 ota.env（slot=b, upgrade=1, bootcount=0）→ reboot -f`。

## 5. 四个场景的实测结果

| 场景 | 操作 | 结果（日志证据） |
|---|---|---|
| **normal 正常升级** | p4 预置正常 OTA 包；上电后槽 A 的 agent 自动升级到槽 B | boot1：`checksum OK, writing inactive slot B` → `ota.env updated; rebooting`；boot2：`ota state: slot=b upgrade=1 bootcount=0/3` → `bootcount=1/3` → `state saved` → `booting slot B` → `LAB BOOT OK: slot b`；最终 `ota.env`：slot=b/upgrade=0/bootcount=0 |
| **bad 坏包拒绝** | p4 包被篡改 1 字节，sha256 文件保留原值 | boot1：`expected hash ... actual hash ...` → `OTA REJECTED: checksum mismatch (bad package NOT applied)` → 继续 `LAB BOOT OK: slot a`；最终 slot=a |
| **rollback 坏镜像回退** | p4 预置“启动即失败”的槽 B 镜像 | boot1 A 安装后重启；boot2/3/4：`bootcount=1/3, 2/3, 3/3` 均 `LAB BOOT FAIL`；boot5：`bootcount=4/3` → `!!! ROLLBACK -> slot a` → `state saved` → `LAB BOOT OK: slot a`；最终 slot=a |
| **fit_hash_fallback 哈希校验回退** | 人为破坏 FAT 中 `slot_a.itb` 的一个字节 | boot1：`bootm failed for slot A (bad FIT/hash); trying other slot` → 加载槽 B → `LAB BOOT OK: slot b`；最终 slot=b |

## 6. U-Boot 环境变量持久化验证（`test-env.sh`）

```
第 3 步（saveenv）:
  Loading Environment from FAT... Unable to read "uboot.env" from virtio0:1...
  Saving Environment to FAT... OK
  ENV_SAVE_DONE testvar=hello_uboot_persist

第 4 步（FAT 内容）:
  UBOOT    ENV    131072   uboot.env

第 5 步（重启后读回）:
  Loading Environment from FAT... OK
  [boot.scr] persisted env var: testvar=hello_uboot_persist
  LAB BOOT OK: slot a
```
证据：`results/m2/m2-env-save.log`、`results/m2/m2-env-load.log`。

## 7. 踩坑记录（都已在 QEMU 上复现并给出对策）

| 现象 | 原因 | 对策 |
|---|---|---|
| `Loading Environment from FAT... Unable to read` 后 `saveenv` 报 `Saving Environment to nowhere... not possible` | defconfig 同时开了 `ENV_IS_NOWHERE`，且 env_load 优先选中 nowhere | 在配置片段里 `# CONFIG_ENV_IS_NOWHERE is not set`，让 FAT 成为唯一 env 后端 |
| `ext4write` 报 `Unsupported RO compat features found 00000400, not writing` | data 分区默认带 metadata_csum，U-Boot ext4 写不支持 | data 分区用 `mke2fs -O ^metadata_csum,^metadata_csum_seed,^64bit,^orphan_file` |
| FIT 内 gzip 内核：`Uncompressing Kernel Image to 80200000` 后内核无输出/挂起（U-Boot 有 CONFIG_GZIP=y） | 本 QEMU/U-Boot 组合下该解压启动路径异常（未深挖，属目标外） | 改用**未压缩 FIT**（25MB/槽，FAT 64MiB 可容纳两槽）；哈希校验、A/B 机制不变 |
| boot.scr 里的 `source` 执行中不能用同一块内存做 env 导出 | env export 缓冲区若与脚本区（0x8e000000）重叠会破坏正在执行的脚本 | 单独用 `envaddr=0x87000000` 做 env 读写缓冲 |
| `booti` 直接传 U-Boot 自己的控制 FDT 报 `Failed to reserve memory for fdt` | QEMU RISC-V 默认 `fdt_high=~0`，FDT 在 U-Boot 内存区内 | boot.scr 中 `setenv fdt_high` / `setenv initrd_high`（M1-A4 的 booti 路径） |

## 8. 与生产 OTA 的差异（学习时要注意的点）

| 生产做法 | 本实验 | 说明 |
|---|---|---|
| 包签名验证（RSA/ECDSA，U-Boot FIT 签名或 OTA 框架） | 仅 sha256 完整性校验 | 签名密钥管理/验签链可后续扩展 |
| dm-verity / 只读 rootfs 校验 | 无 | 生产常配合 dm-verity 防篡改 |
| 差分升级 | 整包（rootfs 镜像 gz） | 差分算法（bsdiff/erofs 增量）不在目标内 |
| 硬件看门狗（失败自动复位） | guest `reboot -f` 模拟复位（QEMU `-no-reboot` 让测试脚本自动开始下一次上电） | QEMU 无真实看门狗，用测试驱动模拟 |
| 掉电/断电安全 | 状态先写 `ota.env` 再重启，模拟最小原子性 | 真实产品还需考虑写入顺序与双备份 |
| 升级通道（网络/差分包下载） | 包预置在 data 分区（模拟已下载） | 网络不是目标，未启用网络设备 |

## 9. 复现命令

```powershell
# 一次性跑四个场景（约 3 分钟）
wsl -d Ubuntu-24.04 -e bash -lc "COMPRESSION=none bash 02-uboot-ota/test-ota.sh"
# 单独构建 A/B 盘（可选场景 none/normal/bad/broken/corruptfit）
wsl -d Ubuntu-24.04 -e bash -lc "SCENARIO=none bash 02-uboot-ota/mk-ab-disk.sh"
# 验证 U-Boot env 落盘 FAT
wsl -d Ubuntu-24.04 -e bash 02-uboot-ota/test-env.sh
```

## 10. 证据文件索引（`results/m2/`）

| 文件 | 说明 |
|---|---|
| `normal/boot1.log`、`normal/boot2.log`、`normal/final-ota.env` | 正常升级：OTA 写入 + 槽 B 启动确认 |
| `bad/boot1.log`、`bad/final-ota.env` | 坏包校验失败拒绝 |
| `rollback/boot1..boot5.log`、`rollback/final-ota.env` | bootcount 1→4、回退槽 A |
| `fit_hash_fallback/boot1.log`、`fit_hash_fallback/final-ota.env` | FIT hash 失败自动换槽 |
| `m2-env-save.log`、`m2-env-load.log` | U-Boot env 持久化到 FAT 的验证 |
| `boot.scr` | 最终使用的启动脚本二进制 |

# 02-uboot-ota — U-Boot 磁盘启动与 A/B OTA 回滚

本目录对应五阶段启动链中**第三阶段（loader）+ 第五阶段（用户态 agent）配合完成的**
分区与 OTA 实验：U-Boot 从磁盘加载内核、A/B 槽位升级、FIT 校验、bootcount 回滚、env 持久化。

## 磁盘布局（256MiB GPT）

| 分区 | 偏移/大小 | 类型 | 内容 | U-Boot 访问 | Linux 访问 |
|---|---|---|---|---|---|
| p1 | 1MiB / 64MiB | EFI System (FAT16) | `boot.scr`、`slot_a.itb`、`slot_b.itb` | `virtio 0:1` | `/dev/vda1` |
| p2 | 65MiB / 48MiB | Linux fs (ext4) | rootfs A | `virtio 0:2` | `/dev/vda2` |
| p3 | 113MiB / 48MiB | Linux fs (ext4) | rootfs B | `virtio 0:3` | `/dev/vda3` |
| p4 | 161MiB / 32MiB | Linux fs (ext4) | `ota.env`、`pkg/`（OTA 包） | `virtio 0:4` | `/dev/vda4` |

> 说明：本实验中 U-Boot 本身**不在磁盘上**（由 QEMU `-kernel` 加载到 0x80200000）；
> 真机上 U-Boot/SPL 通常在 Flash 裸偏移或独立 boot 分区，由 BootROM/SPL 加载。
> 每个 `slot_?.itb` 是 **kernel+DTB 的 FIT 镜像**（含 sha256），与对应 rootfs 配套。

## 文件说明

| 文件 | 作用 |
|---|---|
| `boot.cmd` / `mk-boot-disk.sh` / `run-disk-boot.sh` | 单槽磁盘启动（M1-A4）：FAT 分区 + boot.scr 加载 Image/initramfs |
| `boot-ab.cmd` / `mk-ab-disk.sh` | A/B 启动脚本 + 完整 A/B 磁盘镜像生成（4 个场景） |
| `mk-fit.sh` | 把 kernel+DTB 打包成带 sha256 的 FIT（`COMPRESSION=gzip|none`） |
| `mk-rootfs.sh` | 生成 BusyBox rootfs（`FAIL=1` 可生成"启动即失败"的坏槽） |
| `ota-agent.sh` | 用户态 OTA agent：sha256 校验 → 写非活动槽 → 置 upgrade 状态 → 重启 |
| `run-ab-boot.sh` | 连续上电测试（模拟升级失败→重启→bootcount 累加→回滚） |
| `test-ota.sh` | 四个 OTA 场景一键测试：normal / bad / broken(rollback) / corruptfit |
| `test-env.sh` | U-Boot env 持久化到 virtio-blk FAT（saveenv/加载）验证 |
| `uboot-fragment.config` | U-Boot S 模式实验配置片段（virtio/块设备/FAT/ext4/环境变量等） |

## A/B 状态机（`boot-ab.cmd`）

状态保存在 p4 的 `ota.env`：`slot`、`upgrade_available`、`bootcount`、`bootlimit`。

```sh
# 读状态
ext4load virtio 0:4 ${envaddr} ota.env && env import -t ${envaddr} ${filesize}

# 待升级：每次尝试新槽 bootcount+1，写回；超限回滚
if test "${upgrade_available}" = "1"; then
  setexpr bootcount ${bootcount} + 1
  if test ${bootcount} -gt ${bootlimit}; then
    # 切换 slot（a<->b）、clear upgrade、reset bootcount
  fi
  env export -t ${envaddr}
  ext4write virtio 0:4 ${envaddr} ota.env ${filesize}
fi

# 按 slot 选 kernel FIT + rootfs，bootm
```

配套关系：**同一个 `slot` 同时决定 `slot_?.itb`（kernel+DTB）和 `rootdev`（rootfs）**；
成功启动后由 rootfs 里的 rcS 写回 `upgrade_available=0, bootcount=0`（"确认成功"）。

## 三种失败与对应机制

| 失败类型 | 检测者 | 机制 | 场景 |
|---|---|---|---|
| OTA 包损坏 | 用户态 agent | sha256 失败 → 拒绝安装，保留原槽 | `bad` |
| FIT 内 kernel/镜像损坏 | **U-Boot** | `bootm` 校验 hash 失败 → 直接换槽 | `corruptfit` |
| 新槽启动后失败 | **U-Boot** | bootcount+1 持久化，超 bootlimit → 回滚 | `broken` → `rollback` |

## 快速开始

```bash
# 前置：工具链/模拟器（见根 README），并已构建
bash scripts/fetch-sources.sh
bash scripts/fetch-opensbi.sh
bash 00-env/build-busybox.sh
bash 01-boot-chain/01-opensbi/build-opensbi.sh
bash 01-boot-chain/03-uboot-s/build-uboot-s.sh
bash 01-boot-chain/05-kernel/build-kernel.sh     # 首次编译较慢

# 四个场景全跑（本实验 U-Boot 下 gzip FIT 会挂起，统一用未压缩 FIT）
export COMPRESSION=none
bash 02-uboot-ota/test-ota.sh

# 或只跑回滚场景（自动连续上电，观察 bootcount 累加与 ROLLBACK）
export COMPRESSION=none
SCENARIO=broken bash 02-uboot-ota/mk-ab-disk.sh
TAG=rollback MAX_BOOTS=8 BOOT_TIMEOUT=30 bash 02-uboot-ota/run-ab-boot.sh
```

### 回滚场景的预期日志（实测）

```
----- power-on #2 -----
[boot.scr] ota state: slot=b upgrade=1 bootcount=0/3
[boot.scr] pending upgrade attempt: bootcount=1/3 slot=b
[boot.scr] >>> booting slot B: slot_b.itb, root=/dev/vda3
LAB BOOT FAIL: slot b is intentionally broken
...
----- power-on #5 -----
[boot.scr] ota state: slot=b upgrade=1 bootcount=3/3
[boot.scr] pending upgrade attempt: bootcount=4/3 slot=b
[boot.scr] !!! ROLLBACK -> slot a (too many failed boots)
[boot.scr] >>> booting slot A: slot_a.itb, root=/dev/vda2
LAB BOOT OK: slot a
```

最终 `ota.env`：`slot=a, upgrade_available=0, bootcount=0, bootlimit=3`。

## 备注

- **env 持久化**：普通 U-Boot 环境存 FAT 的 `uboot.env`；A/B 状态存 p4 的 `ota.env`。
- **ext4 可写要求**：U-Boot 的 `ext4write` 不支持 metadata_csum/64bit/orphan_file，
  所以 data 分区必须用 `mke2fs -O ^metadata_csum,^metadata_csum_seed,^64bit,^orphan_file`。
- **已知限制**：本实验 U-Boot 配置下 FAT 中的 gzip 压缩 FIT 会在解压阶段挂起；
  因此 OTA 实验统一使用 `COMPRESSION=none`（未压缩 FIT），哈希/校验机制不变。
- 脚本已把 QEMU 的 stdin 重定向为 `/dev/null`（交互终端下避免 QEMU `-nographic` 无输出）。

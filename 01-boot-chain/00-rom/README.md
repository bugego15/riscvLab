# 01-boot-chain/00-rom — 第一阶段：复位后的第一段代码

本目录对应五阶段启动链的**第一阶段**：CPU 从复位后的 PC 取第一条指令开始，到把控制权交给下一级为止。

## 启动链位置

```
QEMU 复位(PC=0x1000, M 模式)
  → 内置复位向量(6 条指令): 取 hartid/DTB/入口，跳到 0x80000000
  → stage0    (本目录, M 模式, 0x80000000)   ← 自写"BootROM 替身"（第一阶段主体）
  → OpenSBI   (M 模式, 0x80200000)          ← 定制 FW_TEXT_START=0x80200000 / FW_JUMP_ADDR=0x80400000
  → stage1    (本目录, S 模式, 0x80400000)   ← 自写验证 payload（通过 SBI 打印）
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `stage0.S` | M 模式入口汇编：设栈、保存 a0(hartid)/a1(DTB)、调用 C 主函数，最后原样传参并跳转 OpenSBI |
| `stage0.c` | 第一阶段 C 逻辑：轮询 16550 UART 打印 banner、hartid、DTB 地址、校验 FDT magic |
| `stage0.ld` | stage0 链接脚本（`. = 0x80000000`，带 4KB 栈） |
| `stage1.S` | S 模式入口汇编：设栈、调用 C 主函数、结束后 `wfi` |
| `stage1.c` | S 模式 payload：通过 SBI `ecall`（DBCN/legacy console）打印 SBI 规范版本与实现版本 |
| `stage1.ld` | stage1 链接脚本（`. = 0x80400000`） |
| `build-rom.sh` | 编译 stage0/stage1，并构建定制加载地址的 OpenSBI `fw_jump` |
| `run-stage0.sh` | 启动 QEMU 跑完整链路，串口日志写入 `~/riscv-lab/logs/`，并打印关键行 |
| `gdb-stage0.sh` | 用 `-S -s` 启动 QEMU，GDB 在复位向量→stage0→OpenSBI→stage1 各入口观察寄存器 |

## 关键交接约定

- 复位向量后：`a0 = hartid`、`a1 = DTB 物理地址`、`a2 = fw_dynamic_info 指针`（本实验 stage0 不使用 a2）；
- stage0 跳 OpenSBI 前必须保持：`a0 = hartid`、`a1 = DTB`；
- OpenSBI 跳 stage1 时把 DTB 换成它整理后的地址（本实验为 0x82400000），stage1 应使用 a1 而不是假设原地址。

## 构建与运行

```bash
# 依赖：qemu-system-misc gcc-riscv64-linux-gnu gdb-multiarch make git
# OpenSBI 源码（首次）：
bash scripts/fetch-opensbi.sh

# 编译 + 运行
bash 01-boot-chain/00-rom/build-rom.sh
bash 01-boot-chain/00-rom/run-stage0.sh

# GDB 单步观察（每级入口的 pc/sp/a0/a1/mstatus/sstatus）
bash 01-boot-chain/00-rom/gdb-stage0.sh
```

产物路径（默认 `BUILD_ROOT=~/riscv-lab`）：

- `build/rom/stage0.bin`、`build/rom/stage0.elf`
- `build/rom/stage1.bin`、`build/rom/stage1.elf`
- `build/rom/fw_jump_0x80200000.bin`
- 日志：`logs/m1-a0-stage0-opensbi-stage1.log`

## 观察点（判读标准）

| 观察 | 期望值 |
|---|---|
| 复位 PC | `0x1000`（QEMU 复位向量） |
| 单步 6 条后 | `pc=0x80000000, a0=0(hartid), a1=0x9fe00000(DTB)`（512MB 内存时） |
| stage0 打印 | hartid=0、DTB=0x9fe00000、FDT magic raw LE=`0xedfe0dd0`（大端 `0xd00dfeed`） |
| OpenSBI 打印 | `Firmware Base=0x80200000`、`Domain0 Next Address=0x80400000`、`Next Mode=S-mode` |
| stage1 打印 | `SBI spec version=0x03000000`（3.0）、`impl id=0x1`（OpenSBI）、`impl version=0x10007`（1.7） |
| 结束方式 | stage1 循环 `wfi`，`run-stage0.sh` 的 `timeout` 到点后结束 QEMU |

## 备注

- 本实验的"第一阶段"在真机上是 BootROM（还要做 DDR 初始化、从 Flash 读镜像、校验、恢复模式等）；QEMU 的复位向量只做传参+跳转，stage0 演示的是"接管后的第一段自写代码"。
- 脚本已把 QEMU 的 stdin 重定向为 `/dev/null`：交互式终端里直接运行脚本时，若 stdin 是 TTY、stdout 是管道，QEMU `-nographic` 可能没有任何输出（日志 0 字节）。手工运行 QEMU 时也请加 `< /dev/null`。

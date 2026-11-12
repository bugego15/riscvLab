# 01-boot-chain/01-opensbi — 第二阶段：M 模式固件（SBI 提供者）

本目录对应五阶段启动链的**第二阶段**：0x80000000 处的 M 模式固件。本实验使用 **OpenSBI v1.7**。

## 启动链位置

```
QEMU 复位向量(0x1000, M)
  → 第一阶段 stage0 (M, 0x80000000)      ← ../00-rom，传参后跳转
  → 第二阶段 OpenSBI (M, 0x80000000)     ← 本目录（构建/观察）
  → 下一级 payload (S, 0x80200000)       ← 本目录演示 payload（复用 ../00-rom/stage1.S/.c）
```

OpenSBI 在 M 模式完成：保存启动参数 → 自身初始化（scratch/栈/heap/BSS）→ 平台发现（DTB）→
最小平台设施（UART console、定时器、IPI、复位/关机、PMU）→ PMP/Domain 隔离与中断委托 →
建立 SBI 运行时（trap handler + 扩展表）→ 确定下一级地址/模式 → `mret` 进入 S 模式。

## 文件说明

| 文件 | 作用 |
|---|---|
| `build-opensbi.sh` | 源码构建 OpenSBI（`PLATFORM=generic`），产出 `fw_dynamic.bin/.elf`、`fw_jump.bin/.elf` |
| `build-payload.sh` | 编译演示用 S 模式 payload：复用 `../00-rom/stage1.S/.c`，重链接到 **0x80200000** |
| `payload-0x80200000.ld` | payload 链接脚本（`. = 0x80200000`） |
| `run-opensbi.sh` | 运行 `fw_dynamic + payload`，抓取 OpenSBI 日志与 payload 的 SBI 打印 |
| `gdb-handoff.sh` | GDB 观察 M→S 交接：复位 → OpenSBI 入口(M) → `sbi_hart_switch_mode` → `mret` 前/后 |

## 快速开始

```bash
# 依赖：qemu-system-misc gcc-riscv64-linux-gnu gdb-multiarch make git
# OpenSBI 源码（首次，gitee 镜像）：
bash scripts/fetch-opensbi.sh

# 1) 构建 OpenSBI
bash 01-boot-chain/01-opensbi/build-opensbi.sh

# 2) 构建演示 payload（0x80200000）
bash 01-boot-chain/01-opensbi/build-payload.sh

# 3) 运行：OpenSBI(M) -> payload(S)
bash 01-boot-chain/01-opensbi/run-opensbi.sh

# 4) GDB 看交接时刻
bash 01-boot-chain/01-opensbi/gdb-handoff.sh
```

### 预期输出（关键行）

```
OpenSBI v1.7
Platform Name               : riscv-virtio,qemu
Firmware Base               : 0x80000000
Runtime SBI Version         : 3.0
Standard SBI Extensions     : time,rfnc,ipi,base,hsm,srst,pmu,dbcn,...
Domain0 Next Address        : 0x0000000080200000
Domain0 Next Arg1           : 0x000000009fe00000
Domain0 Next Mode           : S-mode
[stage1] self-written S-mode payload @0x80400000
[stage1] SBI spec version = 0x0000000003000000
[stage1] SBI impl id      = 0x0000000000000001
[stage1] SBI impl version = 0x0000000000010007
```

> 说明：演示 payload 复用第一阶段的 `stage1.c`，其中打印字符串写的是 `@0x80400000`（第一阶段的链接地址）；
> 本目录的 payload 实际链接在 0x80200000，打印内容不影响结论（也可自行改字符串）。

## GDB 观察判读

`gdb-handoff.sh` 依次停在 5 个点，实测值参考：

| 观察点 | 期望 |
|---|---|
| ① 复位瞬间（PC=0x1000） | `a0/a1/a2=0`；`mstatus.MPP=0` |
| ② OpenSBI 入口 0x80000000（M） | `a0=hartid, a1=DTB(0x9fe00000), a2=0x1028`（动态信息指针） |
| ③ `sbi_hart_switch_mode` 入口 | `a0=hartid, a1=DTB, a2=0x80200000(next_addr), a3=1(S-mode), a4=0` |
| ④ mret 前 | `mstatus.MPP=1`（S）、`mepc=0x80200000` |
| ⑤ `mret` 后在 0x80200000 | PC=0x80200000，已进入 S 模式，a0/a1 继续传递 |

换变体观察（例如 `fw_jump`，下一级地址来自编译常量；实测它还会把 DTB 搬到 0x82200000）：

```bash
FW=$HOME/riscv-lab/images/fw_jump.bin FWELF=$HOME/riscv-lab/images/fw_jump.elf \
  bash 01-boot-chain/01-opensbi/gdb-handoff.sh
```

## 关键概念

- **SBI**：S 模式通过 `ecall` 调用 M 模式固件的标准接口（a7=EID、a6=FID、a0-a5 入参，返回 a0=错误码、a1=值）。
- **M→S 交接**：`sbi_hart_switch_mode` 写 `mstatus.MPP=S`、`mepc=next_addr`，然后 `mret`。
- **fw_dynamic vs fw_jump**：前者从 `a2` 指向的 `fw_dynamic_info` 读下一级地址/模式；后者用编译常量 `FW_JUMP_ADDR`（并把 DTB 搬到 `FW_JUMP_FDT_ADDR`）。
- **Domain/PMP**：OpenSBI 用自己的代码/数据区（`Domain0 Region03/04`，`S/U: ()`）隔离 M 模式固件，S/U 无权读写。

## 备注

- 脚本已把 QEMU 的 stdin 重定向为 `/dev/null`：交互式终端下若 stdin 是 TTY、stdout 是管道，QEMU `-nographic` 可能没有任何输出。
- 构建根默认 `~/riscv-lab`，可用环境变量覆盖：`BUILD_ROOT=/path/to/build bash ...`

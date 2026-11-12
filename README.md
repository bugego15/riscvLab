# riscvLab — RISC-V 启动流程学习实验

在 QEMU `-M virt` 上学习 RISC-V 启动流程的代码仓库。按"五阶段启动链"组织，当前已上传 **第一阶段**。

## 五阶段启动链

| 阶段 | 内容 | 状态 |
|---|---|---|
| **1** | 复位后第一段代码（真机 BootROM / 本仓库自写 stage0） | ✅ 已上传（`01-boot-chain/00-rom/`） |
| 2 | M 模式固件（SBI 提供者，OpenSBI） | 后续 |
| 3 | 二级 loader（U-Boot / SPL） | 后续 |
| 4 | 内核加载协议（booti / FIT / QEMU -kernel） | 后续 |
| 5 | 应用层 init（initramfs / rootfs） | 后续 |

## 第一阶段做什么

QEMU `virt` 复位后 `PC = 0x1000`，执行 6 条复位向量指令，然后跳到 `0x80000000`：

```
复位(M模式, PC=0x1000)
  auipc t0, 0x0          # t0 = 0x1000
  addi  a2, t0, 40       # a2 = 0x1028（fw_dynamic_info 指针）
  csrr  a0, mhartid      # a0 = hartid
  ld    a1, 32(t0)       # a1 = *(0x1020) = DTB 物理地址
  ld    t0, 24(t0)       # t0 = *(0x1018) = 下一级入口
  jr    t0               # 跳到 0x80000000
```

真机上这个位置是 **BootROM**；QEMU 上只是"取 hartid/DTB/入口并跳转"的最小桩。
本仓库用两段自写代码补出"扩展版第一阶段"：

1. **`stage0.S` + `stage0.c`（M 模式，第一阶段主体）**：建栈、保存 a0/a1、轮询 16550 UART 打印、校验 DTB magic，然后把 hartid/DTB 原样传给 OpenSBI 并跳转；
2. **`stage1.S` + `stage1.c`（S 模式，验证 payload）**：通过 SBI `ecall` 打印 SBI 规范版本/实现版本，证明 OpenSBI 已经就位。

完整启动链：

```
QEMU 复位向量(0x1000)
  → stage0 (M, 0x80000000)      自写"BootROM 替身"
  → OpenSBI (M, 0x80200000)     定制 FW_TEXT_START/FW_JUMP_ADDR
  → stage1 (S, 0x80400000)      自写 S 模式 payload（通过 SBI 打印）
```

## 环境要求

- Linux / WSL2 Ubuntu（**推荐 WSL2**）
- 依赖工具：

```bash
sudo apt update
sudo apt install -y qemu-system-misc gcc-riscv64-linux-gnu gdb-multiarch make git
```

- 构建根默认 `~/riscv-lab`，可用环境变量覆盖：`BUILD_ROOT=/path/to/build bash ...`
- 需要 OpenSBI v1.7 源码（`scripts/fetch-opensbi.sh` 会从 gitee 镜像下载）

## 快速开始

```bash
git clone https://github.com/bugego15/riscvLab.git
cd riscvLab

# 1) 下载 OpenSBI v1.7 源码（gitee 镜像）
bash scripts/fetch-opensbi.sh

# 2) 编译 stage0/stage1 + 定制 OpenSBI
bash 01-boot-chain/00-rom/build-rom.sh

# 3) 运行（QEMU 约 20 秒后自动结束）
bash 01-boot-chain/00-rom/run-stage0.sh

# 4) 可选：GDB 逐级单步（复位向量 → stage0 → OpenSBI → stage1）
bash 01-boot-chain/00-rom/gdb-stage0.sh
```

> 如果所在网络访问 GitHub 受限（例如 WSL 内直连被墙），可以用 gh-proxy 镜像克隆：
> `git clone https://gh-proxy.com/https://github.com/bugego15/riscvLab.git`

### 预期输出（关键行）

```
[stage0] self-written first-stage code (BootROM substitute)
[stage0] hartid = 0x0000000000000000
[stage0] DTB    = 0x000000009fe00000
[stage0] FDT magic (raw LE) = 0x00000000edfe0dd0
[stage0] handoff -> OpenSBI fw_jump @0x80200000
OpenSBI v1.7
Firmware Base               : 0x80200000
Domain0 Next Address        : 0x0000000080400000
Domain0 Next Mode           : S-mode
[stage1] SBI spec version = 0x0000000003000000
[stage1] SBI impl id      = 0x0000000000000001
[stage1] SBI impl version = 0x0000000010007
```

日志会同时写到 `~/riscv-lab/logs/m1-a0-stage0-opensbi-stage1.log`。

## 目录结构

```
riscvLab/
├─ README.md
├─ 01-boot-chain/
│  └─ 00-rom/                 第一阶段：复位后的第一段代码
│     ├─ stage0.S / stage0.c   M 模式 stage0（BootROM 替身）
│     ├─ stage0.ld             链接脚本（0x80000000）
│     ├─ stage1.S / stage1.c   S 模式验证 payload
│     ├─ stage1.ld             链接脚本（0x80400000）
│     ├─ build-rom.sh          编译 stage0/stage1 + 定制地址的 OpenSBI
│     ├─ run-stage0.sh         一键运行并抓串口日志
│     └─ gdb-stage0.sh         GDB 逐级单步（复位→stage0→OpenSBI→stage1）
└─ scripts/
   ├─ common.sh                公共路径/版本变量
   └─ fetch-opensbi.sh         下载 OpenSBI v1.7 源码
```

## 说明

- 所有实验都在 QEMU `-M virt` 上完成，不依赖真实硬件。
- 本仓库是完整学习实验（启动链 / 分区 OTA / 内存 / 进程）的**第一阶段摘录**，后续阶段会陆续上传。
- 脚本默认把源码放在 `~/riscv-lab/src`、构建产物放在 `~/riscv-lab/build`，可用 `BUILD_ROOT` 环境变量改到其他目录。

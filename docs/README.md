# docs/ — 原理与测试手册

本目录是完整学习实验的原理/测试文档，配合仓库代码使用。建议阅读顺序：

1. `00-principles-and-testing.md`：**主手册**——启动全流程原理（关键概念、复位向量、五阶段交接、
   内存/进程/OTA 原理、QEMU 与真机差异）+ 每个阶段"怎么测、观察什么、期望输出、失败判读"；
2. `01-boot-flow.md`：五阶段启动链的阶段划分与每级职责；
3. `02-uboot-ota.md`：U-Boot 磁盘启动、分区布局、A/B OTA 与回滚；
4. `03-memory.md`：memblock → 页表（Sv39/Sv57）→ buddy → SLUB → slub_debug；
5. `04-process.md`：task_struct/PID1/kthreadd、fork/exec/wait、调度 tracepoint、COW；
6. `05-summary.md`：整体复盘、关键地址/寄存器/日志对照、经验与限制。

| 文档 | 内容 |
|---|---|
| `00-principles-and-testing.md` | 原理 + 各阶段测试方法/判读（主手册） |
| `01-boot-flow.md` | 启动链五阶段总览 |
| `02-uboot-ota.md` | 分区、boot.scr、A/B OTA、回滚、env 持久化 |
| `03-memory.md` | 内核内存管理实验手册 |
| `04-process.md` | 进程管理实验手册 |
| `05-summary.md` | 总结与经验 |

> 说明：文档中提到的 `results/` 是完整实验仓的本地结果目录（启动日志、GDB transcript 等）。
> 本仓库**不包含这些生成物**；按对应脚本重新运行即可生成（默认日志在 `~/riscv-lab/logs/`，
> 部分脚本会复制到 `~/riscv-lab/build/results/`）。
>
> 文档里的命令路径已按本仓库结构书写（`01-boot-chain/...`、`02-uboot-ota/...`、`lab/...`）。

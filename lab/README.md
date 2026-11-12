# lab/ — M3 内存管理 + M4 进程管理实验

共享实验框架：一个 BusyBox initramfs + 内核模块 + 静态测试程序，按内核 cmdline
`lab.mode=<mode>` 分发到不同实验脚本，跑完自动 `poweroff`。日志在 `~/riscv-lab/logs/lab-<mode>.log`，
同时复制到 `~/riscv-lab/build/results/m3|m4/`。

## 实验一览

| 主题 | 模式 | 内容 |
|---|---|---|
| **M3 内存管理** | `meminit` | 内核内存初始化证据：`memblock=debug`、`/proc/iomem`、`/proc/meminfo`、`Virtual kernel memory layout`、debugfs memblock |
| | `pgwalk` | 页表 walk：`satp`/Sv39/Sv48/Sv57、5 级表项、叶表项物理地址与权限位 |
| | `buddy` | buddy 分配器：`alloc_pages(order=0..9)`、`/proc/buddyinfo` 前后对比、`kmem:mm_page_alloc` tracepoint |
| | `slab` | SLUB：`kmem_cache_create`、对象步长、`/proc/slabinfo`、`/sys/kernel/slab/lab_cache` 统计 |
| | `slubdebug` | `slub_debug=FZ` 红区越界检测：`Redzone overwritten`、`BUG kmalloc-32` |
| **M4 进程管理** | `proc` | `/proc/1/status`、`task_struct` 链表遍历（init_task/PID1/kthreadd/内核线程）、fork/exec/wait、`sched_switch/sched_wakeup` tracepoint、COW（`smaps_rollup`） |

## 文件说明

| 路径 | 作用 |
|---|---|
| `mods/` | 内核模块：`buddy_demo.c`、`slab_demo.c`、`pgwalk_demo.c`、`slub_debug_demo.c`、`task_walk.c` + `Makefile` |
| `tests/` | 静态测试程序：`fork_exec.c`（fork/exec/wait）、`cow_test.c`（COW + smaps_rollup） |
| `overlay/` | 实验脚本：`init`（PID1）、`run-<mode>.sh`（各实验）、`run-proc.sh`（M4） |
| `build-lab.sh` | 编译外部内核模块 + 静态测试程序（需要内核构建产物 `Module.symvers`） |
| `mk-lab-initramfs.sh` | 打包 BusyBox + 模块 + 测试程序 + overlay 成 `lab-initramfs.cpio.gz` |
| `run-lab.sh` | 启动 QEMU 跑指定 `LAB_MODE`，抓日志并复制结果 |

## 前置依赖

```bash
# 工具链/模拟器（见根 README）+ 已构建：
bash scripts/fetch-opensbi.sh
bash scripts/fetch-sources.sh
bash 00-env/build-busybox.sh
bash 01-boot-chain/05-kernel/build-kernel.sh    # 需要内核构建产物（含 vmlinux.symvers）
```

## 快速开始

```bash
# 构建模块/测试程序 + initramfs
bash lab/build-lab.sh
bash lab/mk-lab-initramfs.sh

# M3
LAB_MODE=meminit LAB_EXTRA="memblock=debug" bash lab/run-lab.sh
LAB_MODE=pgwalk  bash lab/run-lab.sh
LAB_MODE=buddy   bash lab/run-lab.sh
LAB_MODE=slab    bash lab/run-lab.sh
LAB_MODE=slubdebug LAB_EXTRA="slub_debug=FZ" bash lab/run-lab.sh

# M4
LAB_MODE=proc bash lab/run-lab.sh
```

可调环境变量：`LAB_TIMEOUT`（默认 180s）、`LAB_EXTRA`（追加内核 cmdline）、`FW_JUMP`。

## 预期关键输出（实测）

### M3-C1 meminit

```
Memory: 464672K/524288K available (... 56288K reserved)
OF: reserved mem: 0x80000000..0x8003ffff (256 KiB) nomap non-reusable mmode_resv1@80000000
/proc/iomem:
80000000-8004ffff : Reserved
80050000-9fffffff : System RAM
Virtual kernel memory layout:
  fixmap/vmemmap/vmalloc/lowmem  (Sv57 布局，lowmem 512 MB)
```

### M3-C2 pgwalk

```
pgwalk: satp=a001c00000082d3c mode=Sv57 asid=28 root_ppn=82d3c
pgwalk: mm->pgd=... __pa(mm->pgd)=0x82d3c000
pgwalk: user start_code va=0x10000 Sv57(10) levels=5
  L4 shift=48 / L3=39 / L2=30 / L1=21 / L0=12
  => LEAF L0 phys=0x9ee41000 flags=R-XU-A-
```

### M3-C3 buddy

```
BEFORE: DMA32 10 4 4 2 0 3 2 1 3 2 105
AFTER : DMA32  1 1 2 1 1 3 2 1 3 2 104     # order-10 分裂
FINAL : DMA32  1 1 2 2 2 3 1 1 3 2 105
```

### M3-C4 slab

```
slab_demo: kmem_cache_create("lab_cache", size=64, align=8, ctor) ok
/proc/slabinfo: lab_cache 56 56 72 56 1
/sys/kernel/slab/lab_cache: object_size=64 objs_per_slab=56 order=0 slabs=1
卸载后 lab_cache: gone
```

### M3-C5 slubdebug

```
kmalloc-32 562 756 96 42 1     # slub_debug=FZ 下对象膨胀
[Right Redzone overwritten] ... First byte 0x41 instead of 0xcc
BUG kmalloc-32: Object corrupt
FIX kmalloc-32: Restoring Right Redzone ...=0xcc
```

### M4 proc

```
task_walk: init_task=ffffffff8160d000 init_task.pid=0
task_walk: [ 0] pid=1 comm=init     mm=ff60000003070000     ← PID 1 有 mm
task_walk: [ 1] pid=2 comm=kthreadd mm=0000000000000000     ← 内核线程无 mm
[fork_exec] parent pid=63 ppid=59
[fork_exec] child  pid=64 ppid=63 (after fork)
[fork_exec] exec /bin/echo OK
[fork_exec] parent: child 64 exited, status=0x0 (exit=0)
sched_switch: prev_comm=fork_exec ... ==> next_comm=echo ...
[cow_test] child pid=69 writes p[0]='B' (triggers COW)
[cow_test] parent after child exit: p[0]=A (child's write must not leak)
```

## 判读要点

- **M3**：memblock 管早期物理内存（含 DTB 的 reserved-memory、OpenSBI 的 `mmode_resv`）→ 页表（Sv57，5 级）→ buddy 管页（order）→ SLUB 管对象（kmem_cache）。
- **M4**：`task_struct` 链表从 `init_task` 开始；PID1 `init` 有用户 mm，PID2 `kthreadd` 及内核线程 `mm=NULL`；fork 复制页表（COW），exec 替换地址空间，wait 回收子进程；`sched_switch/sched_wakeup` 展示调度切换。

# RISC-V Linux 内存初始化与分配管理

实验平台：QEMU `-M virt`（512MB），Linux 6.12.117（Sv57 5 级页表）。
实验框架：`lab/`（内核模块 + lab initramfs + runner），证据：`results/m3/`。

## 1. 全景：从 memblock 到 buddy/slab

```
start_kernel()
  → setup_arch()
      → parse_dtb()                 解析 QEMU 传进来的 DTB
      → early memory 扫描            memblock_add() 记录可用物理内存
      → memblock_reserve()          保留 kernel/initrd/DTB/OpenSBI 区域
  → paging_init()
      → 建立内核页表（Sv39/Sv48/Sv57）并把 memblock 管理的内存映射进直接映射区
      → memblock_alloc() 页表页/修页表
  → mm_init()
      → free_area_init()            按 zone（DMA32）初始化 buddy 的 free_area
      → mem_init()                  __free_pages 释放“不再需要的 memblock 页面”给 buddy
  → 之后：
      页分配器 = buddy（/proc/buddyinfo、/proc/pagetypeinfo、kmem tracepoints）
      小对象   = SLUB（/proc/slabinfo、/sys/kernel/slab/*）
```

## 2. 实验与证据

### C1 内存初始化（`memblock=debug`）

启动参数：`lab.mode=meminit memblock=debug`，日志 `results/m3/lab-meminit.log`。

**① memblock 预留（`memblock=debug` 打印）节选：**
```
memblock_reserve: [0x0000000080200000-0x0000000081bfffff] paging_init+0xd6/0x592     ← 内核镜像
memblock_reserve: [0x0000000088200000-0x00000000884eafff] reserve_initrd_mem+0xae    ← initramfs
memblock_reserve: [0x0000000082200000-0x00000000822015b2] paging_init+0x1e6          ← DTB
memblock_reserve: [0x000000009ffff000-0x000000009fffffff] memblock_alloc_range_nid  ← 修页表/少量分配
memblock_alloc_try_nid: 16777216 bytes ... sparse_init+0x62                          ← sparse vmemmap
memblock_alloc_exact_nid_raw: 8388608 bytes align=0x200000 ... memmap_alloc          ← struct page 数组
```

**② Zone 与内存可用量：**
```
Zone ranges:
  DMA32    [mem 0x0000000080000000-0x000000009fffffff]
Early memory node ranges
  node 0: [mem 0x0000000080000000-0x000000008004ffff]   ← OpenSBI M 模式保留区
  node 0: [mem 0x0000000080050000-0x000000009fffffff]
Initmem setup node 0 [mem 0x0000000080000000-0x000000009fffffff]
Virtual kernel memory layout:
  lowmem : 0xff60000000000000 - 0xff60000020000000   ( 512 MB)
Memory: 464956K/524288K available (12045K kernel code, ...)
```

**③ `/proc/iomem`（内核视角的物理地址布局）：**
```
80000000-8004ffff : Reserved                    ← OpenSBI M 模式区（no-map）
80050000-9fffffff : System RAM
  80200000-80201fff : Reserved
  80202000-81aa386f : Kernel image              ← 内核代码/数据/bss
  81aa3870-81bfffff : Reserved                  ← 页表/早期分配
  82200000-82201fff : Reserved                  ← DTB
  88200000-884eafff : Reserved                  ← initramfs
  9e600000-9eff0fff : Reserved                  ← sparse vmemmap 等
  9fff9000-9fffffff : Reserved
```

**④ debugfs memblock（`CONFIG_ARCH_KEEP_MEMBLOCK` + DEBUG_FS）：**
```
/sys/kernel/debug/memblock/memory:
   0: 0x0000000080000000..0x000000008004ffff    0 NOMAP
   1: 0x0000000080050000..0x000000009fffffff    0 NONE
/sys/kernel/debug/memblock/reserved:
   0: 0x0000000080200000..0x0000000081bfffff    0 NONE   ← 内核镜像
   1: 0x0000000082200000..0x00000000822015b2    0 NONE   ← DTB
   ...
  18: 0x000000009eff20c0..0x000000009fff8f7b    0 NONE
```

### C2 页表 walk（Sv57 5 级）

模块 `lab/mods/pgwalk_demo.c`：读 `satp`，按 Sv39/Sv48/Sv57 动态计算顶层 shift，然后**直接解码物理页表**（不依赖未导出的内核辅助函数）。日志：`results/m3/lab-pgwalk.log`。

```
pgwalk: satp=a001c00000082d37 mode=Sv57 asid=28 root_ppn=82d37
pgwalk: current comm=insmod pid=60 mm=ff6000000346cc00 mm->pgd=ff60000002d37000 __pa(mm->pgd)=0000000082d37000
```
→ `__pa(mm->pgd)` 与 satp 根页表物理地址一致，验证“当前进程页表根 = satp”。

用户 `start_code` 的 5 级 walk：
```
L4 shift=48 idx=0   entry=...01
L3 shift=39 idx=0   entry=...01
L2 shift=30 idx=0   entry=...01
L1 shift=21 idx=0   entry=...01
L0 shift=12 idx=16  entry=...5b
=> LEAF L0 phys=000000009ee71000 flags=R-XU-A-
```
内核模块代码（高地址）与直接映射页的 walk 同样成功，PTE 物理地址与权限位（R/W/X/U/G/A/D）都能读出。

### C3 buddy 分配器

模块 `buddy_demo` 依次 `alloc_pages(order=0..9)` 并持有；用户态在分配前后读 `/proc/buddyinfo`，同时打开 `kmem:mm_page_alloc/mm_page_free` tracepoint。日志：`results/m3/lab-buddy.log`。

分配结果（模块打印）：
```
buddy_demo: MAX_PAGE_ORDER=10, PAGE_SIZE=4096
buddy_demo: alloc_pages(order=0) ok pfn=82f20 phys=0x82f20000 size=4KiB
...
buddy_demo: alloc_pages(order=9) ok pfn=83800 phys=0x83800000 size=2048KiB
```
`/proc/buddyinfo` 变化（DMA32 行，order 0 → 10）：
```
BEFORE: DMA32  1  2  2  3  0  3  1  0  2  3  105
AFTER : DMA32  1  2  2  3  1  3  1  0  2  3  104
```
解读：
- `order-10` 空闲块 105 → 104：最大块被分裂；
- `order-4` 空闲块 0 → 1：分裂产生了空闲的 order-4 伙伴；
- 低 order 分配大量来自 **per-CPU 页清单（pcp）**，所以在 buddyinfo 里看不出来 —— 这是初学者最容易误判“分配没生效”的原因。

tracepoint 证据（`mm_page_alloc`）：
```
insmod-61  [000] ...1. mm_page_alloc: pfn=0x81087 order=0 migratetype=1 gfp_flags=GFP_HIGHUSER_MOVABLE|__GFP_COMP
insmod-61  [000] ...1. mm_page_alloc: pfn=0x82e92 order=0 migratetype=0 gfp_flags=GFP_KERNEL
```
（migratetype 区分 UNMOVABLE/MOVABLE 等，buddy 按迁移类型分链表。）

### C4 SLUB 分配器

模块 `slab_demo`：`kmem_cache_create("lab_cache", 64, 8, 0, ctor)` + 8 次 `kmem_cache_alloc` + 各种 `kmalloc`；ctor 用于**阻止 SLUB 合并 cache**（否则 `lab_cache` 不会单独出现在 slabinfo）。日志：`results/m3/lab-slab.log`。

`/proc/slabinfo`（AFTER）中出现独立 cache：
```
lab_cache   56  56  72  56  1 : tunables 0 0 0 : slabdata 1 1 0
kmalloc-64 960 960  64  64  1 : ...
kmalloc-8  4096 4096 8 512 1 : ...
```
`/sys/kernel/slab/lab_cache/`：
```
object_size = 64
objs_per_slab = 64
order = 0
objects = 64
slabs = 1
total_objects = 64
```
结论：`kmem_cache_alloc` 从自己的 slab（order-0 页、64 个 64B 对象）里分配；`rmmod` 后 cache 被销毁、`lab_cache` 从 slabinfo 消失。

### C5 slub_debug 红区检测（故意越界）

启动参数加 `slub_debug=FZ`（F=一致性检查，Z=红区），模块故意把 32 字节对象写 64 字节。日志：`results/m3/lab-slubdebug.log`。

```
[Right Redzone overwritten] 0xff600000030044c0-0xff600000030044c7 @offset=1216. First byte 0x41 instead of 0xcc
BUG kmalloc-32 (Tainted: G O ): Object corrupt
Object 0xff600000030044a0 @offset=1184 fp=0x4141414141414141
Redzone  ff600000030044c0: 41 41 41 41 41 41 41 41   AAAAAAAA
...
WARNING: CPU: 0 PID: 65 at mm/slub.c:1127 object_err
[<...>] slub_debug_demo_init+0x80/0x1000 [slub_debug_demo]
FIX kmalloc-32: Restoring Right Redzone ...
FIX kmalloc-32: Object at 0xff600000030044a0 not freed
```
结论：SLUB 调试能力可以精确检出越界（红区 0xcc 被 0x41 覆盖），并保留调用栈与对象地址。

## 3. 关键结论

1. 启动早期用 **memblock** 管理“物理内存的保留/分配”，此时还没有 buddy；`paging_init` 建立内核页表并保留页表页，`mm_init/free_area_init` 之后 buddy 才接管。
2. RISC-V 内核可以运行在 Sv39/Sv48/Sv57；本实验 QEMU 默认 **Sv57（5 级）**，`satp` 的根页表物理地址与 `mm->pgd` 对应。
3. buddy 按 order 管理 2^n 个连续页；低 order 分配会先命中 per-CPU 页清单（pcp），观察 buddyinfo 时要结合 tracepoint。
4. SLUB 的 `kmem_cache_create` 会按名称/大小合并兼容 cache；需要独立观测时加 ctor（或用 `slab_nomerge`）。
5. `slub_debug=FZ` 能在 `kfree` 时检出红区越界，是内核内存调试的实用手段。

## 4. 复现命令

```powershell
# 构建实验模块/测试程序 + lab initramfs
wsl -d Ubuntu-24.04 -e bash lab/build-lab.sh
wsl -d Ubuntu-24.04 -e bash lab/mk-lab-initramfs.sh
# 逐个实验
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=meminit LAB_EXTRA="memblock=debug" bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=pgwalk  bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=buddy   bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=slab    bash lab/run-lab.sh'
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=slubdebug LAB_EXTRA="slub_debug=FZ" bash lab/run-lab.sh'
```

## 5. 证据文件

`results/m3/`：`lab-meminit.log`、`lab-pgwalk.log`、`lab-buddy.log`、`lab-slab.log`、`lab-slubdebug.log`。

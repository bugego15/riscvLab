# RISC-V Linux 进程管理

实验平台：QEMU `-M virt`，Linux 6.12.117，BusyBox initramfs（lab 框架）。
证据：`results/m4/lab-proc.log`。

## 1. 实验内容

| 编号 | 实验 | 手段 |
|---|---|---|
| P1 | task_struct 链表与进程/线程关系 | 内核模块 `task_walk`：`for_each_process_thread` 遍历 |
| P2 | fork / exec / wait 生命周期 | 静态测试程序 `fork_exec` |
| P3 | 调度切换观测 | tracepoint `sched:sched_switch` / `sched:sched_wakeup` |
| P4 | 写时复制（COW） | `cow_test` + `/proc/self/smaps_rollup` 前后对比 |

## 2. P1：task_struct 链表（模块输出）

```
task_walk: init_task=ffffffff8160d000 init_task.pid=0
task_walk: [ 0] task=ff60000001e20000 pid=1  tgid=1  comm=init        state=8193 mm=ff6000000346c000 stack=ff20000000008000
task_walk: [ 1] task=ff60000001e20e00 pid=2  tgid=2  comm=kthreadd    state=1    mm=0000000000000000 stack=ff20000000010000
task_walk: [ 2] task=ff60000001e21c00 pid=3  tgid=3  comm=pool_workqueue_ state=1 mm=0 ... stack=ff20000000018000
task_walk: [ 3] task=ff60000001e22a00 pid=4  tgid=4  comm=kworker/R-kvfre state=1026 mm=0 ...
task_walk: [ 4] task=ff60000001e23800 pid=5  tgid=5  comm=kworker/R-rcu_g state=1026 mm=0 ...
...
task_walk: current=ff60000003488e00 pid=61 comm=insmod flags=0x400100
```

要点：
- `init_task` 是静态定义的 0 号任务（swapper），所有进程通过 `tasks` 链表挂在其下；
- **PID 1 = init**（本实验由内核直接执行 initramfs 的 `/init`），有 `mm`（用户地址空间）；
- **PID 2 = kthreadd**，内核线程的父进程；内核线程 `mm = NULL`（没有用户地址空间，借用 `active_mm`）；
- 内核线程栈位于 `ff20000000xxxxxx` 区域，每个任务 `stack` 指针对应一段内核栈（RISC-V THREAD_SIZE=16KB）；
- `state` 值：`1`=TASK_RUNNING? 实际取值见 `include/linux/sched.h`（8193=0x2001 含 `TASK_REPORT` 标志位，1026=0x402），`ps` 的 R/S/D 就是从这里解码的。

## 3. P2：fork / exec / wait

```
[fork_exec] parent pid=62 ppid=58
[fork_exec] child  pid=63 ppid=62 (after fork)
[fork_exec] exec /bin/echo OK
[fork_exec] parent: child 63 exited, status=0x0 (exit=0)
```
说明了 `fork()` 复制进程（子进程 pid 63/ppid 62）→ `execl()` 替换映像（执行 `/bin/echo`）→ 父进程 `waitpid()` 回收并得到退出码。

## 4. P3：调度 tracepoint（fork/exec/wait 过程）

```
fork_exec-64 [000] d..3. sched_switch: prev_comm=fork_exec prev_pid=64 prev_state=R ==> next_comm=fork_exec next_pid=65
echo-65      [000] d..3. sched_switch: prev_comm=fork_exec prev_pid=65 prev_state=R ==> next_comm=fork_exec next_pid=64
fork_exec-64 [000] d..3. sched_switch: prev_comm=fork_exec prev_pid=64 prev_state=S ==> next_comm=rcu_sched ...
kworker/0:0-9 ...       sched_switch: prev_comm=kworker/0:0 prev_pid=9 prev_state=I ==> next_comm=run-proc.sh
```
可以从中看到：
- `fork()` 后父/子进程在 CPU 上交替运行（pid 64/65）；
- 父进程 `waitpid()` 阻塞时 `prev_state=S`（sleeping），被唤醒后继续；
- 空闲内核线程（kworker）与用户进程之间的切换；
- 每行包含 CPU、prev/next 任务、优先级、时间戳，是理解调度器最直接的窗口。

## 5. P4：写时复制（COW）

`cow_test`：mmap 16KB 匿名页并写满，fork 后子进程写 `p[0]='B'`，父子各自打印 `/proc/self/smaps_rollup`：

```
[cow_test] mapped 16384 bytes at 0x7fff89139000, touched all pages
[cow_test] before-fork /proc/self/smaps_rollup:
  Rss: 552 kB   Shared_Clean: 4 kB   Private_Dirty: 540 kB   Anonymous: 64 kB
[cow_test] child pid=68 writes p[0]='B' (triggers COW)
[cow_test] child-after-cow /proc/self/smaps_rollup:
  Rss: 460 kB   Shared_Clean: 0 kB   Private_Dirty: 36 kB    Anonymous: 64 kB
[cow_test] parent after child exit: p[0]=A (child's write must not leak)
[cow_test] after-child-cow /proc/self/smaps_rollup:
  Rss: 552 kB   Shared_Clean: 4 kB   Private_Dirty: 540 kB   Anonymous: 64 kB
```
要点：
- fork 后父子共享只读页；子进程写 `p[0]` 时触发 **page fault → 复制一页 → 映射写权限（COW）**；
- 子进程侧的 `smaps_rollup` 发生变化（它自己的 COW 页），父进程数据与统计不变（`p[0]=A`）；
- 生产上 fork+exec 大量使用时，COW 的页复制成本是关注点之一。

## 6. 关键结论

1. `task_struct` 是进程/线程的统一抽象：用户进程有独立 `mm`，内核线程 `mm=NULL`（`active_mm` 借用）；PID 1 与 kthreadd 是所有进程/内核线程的两个“根”。
2. fork 复制地址空间（页表 + COW），exec 替换用户态映像，wait 负责回收僵尸进程。
3. 调度行为可用 `sched_switch/sched_wakeup` tracepoint 直接观测（prev_state、优先级、CPU）。
4. COW 用 `/proc/self/smaps_rollup` 能在用户态清晰验证“复制发生在写时而非 fork 时”。

## 7. 复现

```powershell
wsl -d Ubuntu-24.04 -e bash lab/build-lab.sh
wsl -d Ubuntu-24.04 -e bash lab/mk-lab-initramfs.sh
wsl -d Ubuntu-24.04 -e bash -lc 'LAB_MODE=proc bash lab/run-lab.sh'
```

## 8. 证据文件

`results/m4/lab-proc.log`（task_walk 输出、fork/exec、sched trace、COW smaps、/proc/1/status）。

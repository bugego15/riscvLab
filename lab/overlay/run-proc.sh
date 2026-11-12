#!/bin/sh
# M4：进程管理证据（task_struct / fork-exec / 调度 tracepoint / COW）
TR=/sys/kernel/tracing
[ -d "$TR" ] || TR=/sys/kernel/debug/tracing

echo "===== M4: process management ====="
echo "--- /proc/1/status（head） ---"
head -25 /proc/1/status
echo ""
echo "--- /proc/1/stat ---"
cat /proc/1/stat
echo ""
echo "--- insmod task_walk.ko（遍历 task_struct 链表） ---"
insmod /root/lab/mods/task_walk.ko
echo ""
echo "--- fork / exec / wait 测试 ---"
/root/lab/tests/fork_exec
echo ""
echo "--- 调度 tracepoint：sched_switch / sched_wakeup 观察 fork/exec/wait ---"
if [ -d "$TR/events/sched" ]; then
	echo 1 > "$TR/events/sched/sched_switch/enable" 2>/dev/null
	echo 1 > "$TR/events/sched/sched_wakeup/enable" 2>/dev/null
	echo > "$TR/trace" 2>/dev/null
	/root/lab/tests/fork_exec >/dev/null 2>&1
	echo "--- trace（head 40） ---"
	head -40 "$TR/trace" 2>/dev/null
	echo 0 > "$TR/events/sched/sched_switch/enable" 2>/dev/null
	echo 0 > "$TR/events/sched/sched_wakeup/enable" 2>/dev/null
fi
echo ""
echo "--- COW 写时复制测试（smaps_rollup 前后对比） ---"
/root/lab/tests/cow_test
echo ""
echo "--- /proc/sched_debug（head） ---"
head -20 /proc/sched_debug 2>/dev/null
echo ""
echo "--- rmmod task_walk.ko ---"
rmmod task_walk
echo "=== M4 END ==="

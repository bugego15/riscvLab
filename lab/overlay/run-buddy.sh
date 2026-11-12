#!/bin/sh
# M3-C3：buddy 分配器实验：/proc/buddyinfo 前后对比 + kmem tracepoint
TR=/sys/kernel/tracing
[ -d "$TR" ] || TR=/sys/kernel/debug/tracing

echo "===== M3-C3: buddy allocator ====="
echo "--- /proc/buddyinfo BEFORE ---"
cat /proc/buddyinfo
echo ""
echo "--- /proc/pagetypeinfo BEFORE (head) ---"
head -20 /proc/pagetypeinfo
echo ""
if [ -d "$TR/events/kmem" ]; then
	echo "[lab] enabling kmem:mm_page_alloc / mm_page_free tracepoints"
	echo 1 > "$TR/events/kmem/mm_page_alloc/enable" 2>/dev/null
	echo 1 > "$TR/events/kmem/mm_page_free/enable" 2>/dev/null
	echo > "$TR/trace" 2>/dev/null
fi

echo "--- insmod buddy_demo.ko ---"
insmod /root/lab/mods/buddy_demo.ko
echo ""
echo "--- /proc/buddyinfo AFTER alloc ---"
cat /proc/buddyinfo
echo ""
echo "--- /proc/pagetypeinfo AFTER alloc (head) ---"
head -20 /proc/pagetypeinfo
echo ""
echo "--- trace: kmem:mm_page_alloc (first 40 lines) ---"
head -40 "$TR/trace" 2>/dev/null

if [ -d "$TR/events/kmem" ]; then
	echo 0 > "$TR/events/kmem/mm_page_alloc/enable" 2>/dev/null
	echo 0 > "$TR/events/kmem/mm_page_free/enable" 2>/dev/null
fi
echo ""
echo "--- rmmod buddy_demo.ko ---"
rmmod buddy_demo
echo "--- /proc/buddyinfo FINAL (after free) ---"
cat /proc/buddyinfo
echo "=== M3-C3 END ==="

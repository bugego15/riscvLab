#!/bin/sh
# M3-C1：Linux 内核内存初始化证据（memblock / paging_init / mm_init）
echo "===== M3-C1: Linux memory initialization ====="
echo "--- cmdline ---"
cat /proc/cmdline
echo ""
echo "--- early boot memory lines (dmesg) ---"
dmesg | grep -E 'Memory:|Zone ranges|Early memory node|Initmem setup|reserved mem|Virtual kernel memory layout|fixmap|vmemmap|vmalloc |lowmem|percpu|SLUB|memblock|pgtable|Memory: ' | head -120
echo ""
echo "--- /proc/iomem ---"
cat /proc/iomem
echo ""
echo "--- /proc/meminfo (head) ---"
head -16 /proc/meminfo
echo ""
echo "--- debugfs memblock ---"
for f in /sys/kernel/debug/memblock/memory /sys/kernel/debug/memblock/reserved; do
	if [ -f "$f" ]; then
		echo "== $f"
		head -40 "$f"
	fi
done
echo ""
echo "--- /proc/vmstat (memory counters) ---"
grep -E 'nr_free_pages|nr_slab|nr_page_table_pages|nr_kernel_misc|pgalloc|pgfree' /proc/vmstat
echo "=== M3-C1 END ==="

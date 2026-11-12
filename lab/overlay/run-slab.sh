#!/bin/sh
# M3-C4：SLUB/slab 实验：/proc/slabinfo + /sys/kernel/slab/<cache> 统计
echo "===== M3-C4: SLUB allocator ====="
echo "--- /proc/slabinfo（说明头） ---"
head -2 /proc/slabinfo
echo ""
echo "--- 相关 cache BEFORE ---"
grep -E '^lab_cache|^kmalloc-(8|32|64|1k|4k|8k) ' /proc/slabinfo
echo ""
echo "--- insmod slab_demo.ko ---"
insmod /root/lab/mods/slab_demo.ko
echo ""
echo "--- 相关 cache AFTER（object 数应变化） ---"
grep -E '^lab_cache|^kmalloc-(8|32|64|1k|4k|8k) ' /proc/slabinfo
echo ""
echo "--- /sys/kernel/slab/lab_cache 统计 ---"
for f in object_size objs_per_slab order objects slabs total_objects; do
	if [ -f "/sys/kernel/slab/lab_cache/$f" ]; then
		echo "$f = $(cat /sys/kernel/slab/lab_cache/$f)"
	fi
done
echo ""
echo "--- rmmod slab_demo.ko ---"
rmmod slab_demo
echo "--- 相关 cache FINAL（lab_cache 应消失） ---"
grep -E '^lab_cache ' /proc/slabinfo || echo "lab_cache: gone (cache destroyed)"
grep -E '^kmalloc-(8|32|64|1k|4k|8k) ' /proc/slabinfo
echo "=== M3-C4 END ==="

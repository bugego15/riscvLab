#!/bin/sh
# M3-C5：SLUB 调试（boot 参数 slub_debug=FZ）：红区越界检测
echo "===== M3-C5: SLUB debug redzone (slub_debug=FZ) ====="
echo "--- cmdline ---"
cat /proc/cmdline
echo ""
echo "--- /proc/slabinfo: kmalloc-32 ---"
grep -E '^kmalloc-32 ' /proc/slabinfo
echo ""
echo "--- /sys/kernel/slab/kmalloc-32 调试标志 ---"
for f in red_zone sanity_checks poison store_user; do
	if [ -f "/sys/kernel/slab/kmalloc-32/$f" ]; then
		echo "$f = $(cat /sys/kernel/slab/kmalloc-32/$f)"
	fi
done
echo ""
echo "--- insmod slub_debug_demo.ko（故意越界写 32 字节对象） ---"
insmod /root/lab/mods/slub_debug_demo.ko
echo ""
echo "--- 上面应出现 Redzone overwritten / BUG kmalloc-32 报告 ---"
echo "=== M3-C5 END ==="

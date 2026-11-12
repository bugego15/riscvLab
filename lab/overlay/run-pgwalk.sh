#!/bin/sh
# M3-C2：页表 walk（satp / Sv39|Sv48|Sv57 / 逐级表项 / PTE 物理地址）
echo "===== M3-C2: page table walk ====="
echo "--- /proc/cpuinfo（ISA/MMU 相关信息） ---"
head -40 /proc/cpuinfo
echo ""
echo "--- insmod pgwalk_demo.ko ---"
insmod /root/lab/mods/pgwalk_demo.ko
echo ""
echo "--- rmmod pgwalk_demo.ko ---"
rmmod pgwalk_demo
echo "=== M3-C2 END ==="

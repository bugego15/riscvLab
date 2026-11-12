#!/usr/bin/env bash
# 环境检查：wsl -d Ubuntu-24.04 -e bash 00-env/check-env.sh
set +e
BUILD_ROOT="${BUILD_ROOT:-/home/$(getent passwd 1000 | cut -d: -f1)/riscv-lab}"
fail=0

check() { # check <命令> <说明>
  local p
  p="$(command -v "$1" 2>/dev/null)"
  if [ -n "$p" ]; then
    printf 'OK   %-28s %s\n' "$1" "$p"
  else
    printf 'MISS %-28s (%s)\n' "$1" "$2"
    fail=1
  fi
}

echo "===== 基础命令 ====="
for c in git curl wget tar xz zstd make gcc cpio dtc mkimage mkfs.ext4 mkfs.fat mcopy dd;
do check "$c" "基础工具"; done

echo "===== RISC-V / QEMU ====="
check qemu-system-riscv64 "qemu-system-misc"
check qemu-img "qemu-utils"
check riscv64-linux-gnu-gcc "gcc-riscv64-linux-gnu"
check gdb-multiarch "gdb-multiarch"

echo "===== 版本 ====="
qemu-system-riscv64 --version 2>/dev/null | head -1
riscv64-linux-gnu-gcc --version 2>/dev/null | head -1
gdb-multiarch --version 2>/dev/null | head -1

echo "===== 参考二进制 ====="
ls -l /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin \
      /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin 2>/dev/null
ls -l /usr/lib/u-boot/qemu-riscv64/u-boot.bin \
      /usr/lib/u-boot/qemu-riscv64_smode/u-boot.bin 2>/dev/null
file "${BUILD_ROOT}/tools/busybox-riscv64" 2>/dev/null

echo "===== 构建根 ====="
echo "BUILD_ROOT=${BUILD_ROOT}"
ls -d "${BUILD_ROOT}"/{src,build,images,logs,rootfs,tools} 2>/dev/null

echo "===== 磁盘 ====="
df -h / "${BUILD_ROOT}" 2>/dev/null | tail -2

exit "${fail}"

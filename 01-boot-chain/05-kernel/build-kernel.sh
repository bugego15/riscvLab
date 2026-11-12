#!/usr/bin/env bash
# M0：构建 RISC-V Linux 6.12 内核（Image + vmlinux + 模块准备）
# 用法：wsl -d Ubuntu-24.04 -e bash 01-boot-chain/05-kernel/build-kernel.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../../scripts/common.sh"

[ -d "$KSRC" ] || die "内核源码不存在，先运行 scripts/fetch-sources.sh"
mkdir -p "$KOUT" "$LOGS"

log "配置内核（riscv defconfig + 实验选项）"
make -C "$KSRC" O="$KOUT" ARCH="$KARCH" CROSS_COMPILE="$CROSS" defconfig

# 追加实验需要的内核选项（数组只写符号名，不带 CONFIG_ 前缀和 =y）
CONFIGS=(
  VIRTIO
  VIRTIO_MMIO
  VIRTIO_BLK
  EXT4_FS
  DEVTMPFS
  DEVTMPFS_MOUNT
  BLK_DEV_INITRD
  RD_GZIP
  SERIAL_8250
  SERIAL_8250_CONSOLE
  SERIAL_OF_PLATFORM
  DEBUG_KERNEL
  # 注意：6.12 里 "Compile the kernel with debug info" 是 choice，
  # 真正的符号是 DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT（select DEBUG_INFO）
  DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
  DEBUG_FS
  FTRACE
  FUNCTION_TRACER
  FUNCTION_GRAPH_TRACER
  DYNAMIC_FTRACE
  ARCH_KEEP_MEMBLOCK
  IKCONFIG
  IKCONFIG_PROC
  SCHED_DEBUG
  SCHEDSTATS
  MAGIC_SYSRQ
)
for c in "${CONFIGS[@]}"; do
  "$KSRC/scripts/config" --file "$KOUT/.config" -e "$c"
done
"$KSRC/scripts/config" --file "$KOUT/.config" --set-str LOCALVERSION "-riscv-lab"
make -C "$KSRC" O="$KOUT" ARCH="$KARCH" CROSS_COMPILE="$CROSS" olddefconfig

log "构建 Image（-j${JOBS}）"
make -C "$KSRC" O="$KOUT" ARCH="$KARCH" CROSS_COMPILE="$CROSS" -j"${JOBS}" Image

log "生成 modules_prepare（后续内核模块实验需要）"
make -C "$KSRC" O="$KOUT" ARCH="$KARCH" CROSS_COMPILE="$CROSS" modules_prepare

IMAGE="$KOUT/arch/riscv/boot/Image"
VMLINUX="$KOUT/vmlinux"
[ -f "$IMAGE" ] || die "Image 未生成"
log "完成："
ls -lh "$IMAGE" "$VMLINUX"
file "$IMAGE" "$VMLINUX"

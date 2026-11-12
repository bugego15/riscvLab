#!/usr/bin/env bash
# 构建 riscv64 静态 BusyBox（initramfs 根文件系统来源）
# 用法：wsl -d Ubuntu-24.04 -e bash 00-env/build-busybox.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/../scripts/common.sh"

BBVER="${BBVER:-1.37.0}"
BBDIR="$SRC/busybox-${BBVER}"
BBINSTALL="${BBINSTALL:-${BUILD_ROOT}/rootfs/busybox-install}"

if [ -x "$TOOLS/busybox-riscv64" ]; then
  log "已存在：$TOOLS/busybox-riscv64"
else
  if [ ! -d "$BBDIR" ]; then
    cd "$SRC"
    if [ ! -s "busybox-${BBVER}.tar.bz2" ]; then
      log "下载 BusyBox ${BBVER}"
      curl -fL --retry 3 -o "busybox-${BBVER}.tar.bz2" \
        "https://busybox.net/downloads/busybox-${BBVER}.tar.bz2"
    fi
    log "解压 BusyBox"
    tar xf "busybox-${BBVER}.tar.bz2"
  fi

  log "配置 BusyBox（静态链接）"
  make -C "$BBDIR" ARCH=riscv CROSS_COMPILE="$CROSS" defconfig >/dev/null
  # 静态链接 + 关闭 TC（避免与交叉 libc 头文件的兼容问题）
  sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' "$BBDIR/.config"
  sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' "$BBDIR/.config"
  # 关键：defconfig 会打开 x86 专用的 SHA* HWACCEL，交叉编译到 RISC-V 时符号缺失
  for s in SHA1_HWACCEL SHA256_HWACCEL SHA512_HWACCEL MD5_HWACCEL; do
    sed -i "s/^CONFIG_${s}=y/# CONFIG_${s} is not set/" "$BBDIR/.config"
  done

  log "编译 BusyBox（-j${JOBS}）"
  make -C "$BBDIR" ARCH=riscv CROSS_COMPILE="$CROSS" clean >/dev/null 2>&1 || true
  make -C "$BBDIR" ARCH=riscv CROSS_COMPILE="$CROSS" -j"${JOBS}" >/dev/null

  install -D -m 0755 "$BBDIR/busybox" "$TOOLS/busybox-riscv64"
fi

log "安装 BusyBox 目录树：$BBINSTALL"
rm -rf "$BBINSTALL"
make -C "$BBDIR" ARCH=riscv CROSS_COMPILE="$CROSS" CONFIG_PREFIX="$BBINSTALL" install >/dev/null

log "完成"
file "$TOOLS/busybox-riscv64"
"$TOOLS/busybox-riscv64" 2>/dev/null | head -2 || true
ls "$BBINSTALL/bin" | head -5

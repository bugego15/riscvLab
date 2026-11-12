#!/usr/bin/env bash
# 下载第三阶段需要的源码（Linux 内核 / U-Boot；OpenSBI 用 scripts/fetch-opensbi.sh）
# BusyBox 由 00-env/build-busybox.sh 自行下载。
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/common.sh"

cd "$SRC"
log "源码目录：$SRC"

# 1) Linux 内核（kernel.org）
if [ ! -d "$KSRC" ]; then
  if [ ! -s "linux-${KVER}.tar.xz" ]; then
    log "下载 Linux ${KVER}（约 142MB）"
    curl -fL --retry 3 --retry-delay 3 -o "linux-${KVER}.tar.xz" \
      "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz"
  fi
  log "解压 linux-${KVER}.tar.xz"
  tar xf "linux-${KVER}.tar.xz"
else
  log "内核源码已存在：$KSRC"
fi

# 2) U-Boot（source.denx.de，避开 GitHub）
if [ ! -d "$SRC/u-boot" ]; then
  log "clone U-Boot ${UBOOT_REF}（source.denx.de）"
  git clone --depth 1 --branch "${UBOOT_REF}" https://source.denx.de/u-boot/u-boot.git "$SRC/u-boot"
else
  log "U-Boot 源码已存在：$SRC/u-boot"
fi

log "完成，占用空间："
du -sh "$SRC"/* 2>/dev/null | sort -h

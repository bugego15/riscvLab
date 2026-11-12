#!/usr/bin/env bash
# 公共环境变量：被其他脚本 source
# 用法：source "$(dirname "$0")/../scripts/common.sh"

set -euo pipefail

LAB_ROOT="${LAB_ROOT:-/mnt/d/1212D/riscv-boot-lab}"
TARGET_USER="${TARGET_USER:-$(getent passwd 1000 | cut -d: -f1)}"
BUILD_ROOT="${BUILD_ROOT:-/home/${TARGET_USER}/riscv-lab}"

export LAB_ROOT BUILD_ROOT
export SRC="${BUILD_ROOT}/src"
export BUILD="${BUILD_ROOT}/build"
export IMAGES="${BUILD_ROOT}/images"
export LOGS="${BUILD_ROOT}/logs"
export TOOLS="${BUILD_ROOT}/tools"
export CROSS=riscv64-linux-gnu-
export KARCH=riscv

# 版本（与 00-env/versions.lock 保持一致）
export KVER="${KVER:-6.12.117}"
export OPENSBI_REF="${OPENSBI_REF:-v1.7}"
export UBOOT_REF="${UBOOT_REF:-v2025.10}"

export KSRC="${SRC}/linux-${KVER}"
export KOUT="${BUILD}/linux-${KVER}"
export JOBS="${JOBS:-$(nproc)}"

mkdir -p "$SRC" "$BUILD" "$IMAGES" "$LOGS" "$TOOLS"

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\n[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

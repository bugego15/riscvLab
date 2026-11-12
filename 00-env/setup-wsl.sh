#!/usr/bin/env bash
# M0 环境安装：在 WSL2 Ubuntu 24.04 内以 root 执行
#   wsl -d Ubuntu-24.04 -u root -e bash 00-env/setup-wsl.sh
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export TZ=Asia/Shanghai

TARGET_USER="$(getent passwd 1000 | cut -d: -f1)"
BUILD_ROOT="${BUILD_ROOT:-/home/${TARGET_USER}/riscv-lab}"

echo "== [1/5] apt update =="
apt-get update

echo "== [2/5] 基础工具 + RISC-V 交叉工具链 + QEMU =="
apt-get install -y --no-install-recommends \
  build-essential git curl wget ca-certificates xz-utils zstd file rsync time \
  python3 python3-pyelftools python3-setuptools python3-dev \
  bc bison flex libssl-dev libelf-dev libncurses-dev swig expect \
  qemu-system-misc qemu-utils \
  gcc-riscv64-linux-gnu g++-riscv64-linux-gnu \
  gdb-multiarch device-tree-compiler \
  u-boot-tools mtools dosfstools e2fsprogs cpio

echo "== [3/5] 基线参考二进制：OpenSBI / U-Boot =="
apt-get install -y opensbi u-boot-qemu

echo "== [4/5] 构建根目录 =="
mkdir -p "${BUILD_ROOT}"/{src,build,images,logs,rootfs,tools}
chown -R "${TARGET_USER}:${TARGET_USER}" "${BUILD_ROOT}"

echo "== [5/5] 构建 riscv64 静态 BusyBox（initramfs 用，源码构建） =="
# 注意：不要 dpkg --add-architecture riscv64 —— Ubuntu 主归档是 amd64 的，
# riscv64 包在 ports.ubuntu.com；这里直接用 busybox.net 源码交叉编译，避免依赖 ports。
REPO="${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [ -x "${BUILD_ROOT}/tools/busybox-riscv64" ]; then
  echo "BusyBox 已存在，跳过"
else
  runuser -u "${TARGET_USER}" -- bash "${REPO}/00-env/build-busybox.sh"
fi

echo
echo "== 安装完成 =="
echo "构建根：${BUILD_ROOT}"
qemu-system-riscv64 --version | head -1
riscv64-linux-gnu-gcc --version | head -1
gdb-multiarch --version | head -1
echo "--- apt 版 OpenSBI ---"
ls -l /usr/lib/riscv64-linux-gnu/opensbi/generic/ 2>/dev/null || true
echo "--- apt 版 U-Boot ---"
ls -l /usr/lib/u-boot/qemu-riscv64_smode/ /usr/lib/u-boot/qemu-riscv64/ 2>/dev/null || true
echo "--- busybox ---"
file "${BUILD_ROOT}/tools/busybox-riscv64" 2>/dev/null || true
"${BUILD_ROOT}/tools/busybox-riscv64" 2>/dev/null | head -3 || true

# M1-A4：U-Boot 从 virtio-blk 的 FAT 分区加载 Image + initramfs，用 booti 启动内核
# 由 mk-boot-disk.sh 用 mkimage 打包成 boot.scr 放到 FAT 分区
# 说明：U-Boot RISC-V 的 booti 会按 Image 头 text_offset 把内核重定位到
#       0x80000000 + 0x200000 = 0x80200000，因此 kernel_addr_r 用默认 0x84000000 即可。
echo "=== [boot.scr] U-Boot 启动脚本：从 virtio-blk FAT 分区加载内核 ==="
echo "=== 证明：内核不是 QEMU 直接喂进来的，而是 U-Boot 主动加载 ==="
echo "--- kernel_addr_r=${kernel_addr_r} ramdisk_addr_r=${ramdisk_addr_r} scriptaddr=${scriptaddr}"
# QEMU RISC-V 默认 fdt_high/initrd_high=~0（就地使用），会把 U-Boot 自己的控制 FDT 传给内核，
# 而该 FDT 位于 U-Boot 内存区域内导致预留失败；unset 后由 U-Boot 自动重定位 FDT/initrd。
setenv fdt_high
setenv initrd_high
setenv bootargs "console=ttyS0 earlycon keep_bootcon"
echo "--- fatload Image -> ${kernel_addr_r}"
fatload virtio 0:1 ${kernel_addr_r} Image
echo "--- fatload initramfs.uimg -> ${ramdisk_addr_r}"
fatload virtio 0:1 ${ramdisk_addr_r} initramfs.uimg
echo "--- booti kernel=${kernel_addr_r} ramdisk=${ramdisk_addr_r} fdt=${fdtcontroladdr}"
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdtcontroladdr}
echo "=== booti 返回（失败）==="

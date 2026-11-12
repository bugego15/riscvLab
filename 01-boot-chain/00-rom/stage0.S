# stage0.S —— 自写“BootROM 替身”，QEMU -bios 加载到 0x80000000
# QEMU 复位后：a0 = hartid, a1 = DTB 物理地址
# 职责：建栈 -> 调用 C 代码打印/检查 -> 保留 a0/a1 跳转到下一级（OpenSBI @0x80200000）
    .section .text.init, "ax"
    .globl _start
_start:
    la      sp, _stack_top
    mv      s0, a0                 # 保存 hartid
    mv      s1, a1                 # 保存 DTB 地址
    mv      a0, s0
    mv      a1, s1
    call    boot_main

    # 交接给下一级：OpenSBI fw_jump（构建时 FW_TEXT_START=0x80200000）
    mv      a0, s0                 # a0 = hartid
    mv      a1, s1                 # a1 = DTB
    li      t0, 0x80200000
    jr      t0

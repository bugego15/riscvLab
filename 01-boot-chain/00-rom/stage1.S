# stage1.S —— 自写 S 模式 payload，OpenSBI fw_jump 跳转到此处（0x80400000）
    .section .text.init, "ax"
    .globl _start
_start:
    la      sp, _stack_top
    call    s_mode_main
1:
    wfi
    j       1b

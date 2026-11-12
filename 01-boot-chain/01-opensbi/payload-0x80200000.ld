OUTPUT_ARCH(riscv)
ENTRY(_start)

/* 第二阶段演示 payload：链接到 OpenSBI 交接的下一级地址 0x80200000 */
SECTIONS
{
    . = 0x80200000;
    .text : {
        *(.text.init)
        *(.text*)
    }
    . = ALIGN(16);
    .rodata : { *(.rodata*) }
    . = ALIGN(16);
    .data : { *(.data*) }
    . = ALIGN(16);
    .bss : {
        *(.bss*)
        *(COMMON)
    }
    . = ALIGN(16);
    . += 0x4000;
    _stack_top = .;
}

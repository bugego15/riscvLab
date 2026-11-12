OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
    . = 0x80000000;
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
    . += 0x4000;              /* 16KB 栈空间 */
    _stack_top = .;
}

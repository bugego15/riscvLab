// stage0.c —— 自写 stage0（模拟 BootROM 的职责）
// 只用 16550 UART 做输出，不依赖任何库
typedef unsigned long u64;
typedef unsigned int  u32;
typedef unsigned char u8;

#define UART0_BASE 0x10000000UL

static inline u8 uart_read(u64 off)          { return *(volatile u8 *)(UART0_BASE + off); }
static inline void uart_write(u64 off, u8 v) { *(volatile u8 *)(UART0_BASE + off) = v; }

static void uart_putc(char c)
{
    while ((uart_read(5) & 0x20) == 0)   /* LSR bit5 = THRE */
        ;
    uart_write(0, (u8)c);
}

static void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* 打印完整 16 位十六进制（高位在前） */
static void uart_puthex(u64 v)
{
    static const char hex[] = "0123456789abcdef";
    char buf[16];
    int i;
    for (i = 15; i >= 0; i--) {
        buf[i] = hex[v & 0xf];
        v >>= 4;
    }
    uart_puts("0x");
    for (i = 0; i < 16; i++)
        uart_putc(buf[i]);
}

void boot_main(u64 hartid, u64 dtb)
{
    uart_puts("\r\n");
    uart_puts("[stage0] ================================================\r\n");
    uart_puts("[stage0] self-written first-stage code (BootROM substitute)\r\n");
    uart_puts("[stage0] privilege: M-mode, load addr: 0x80000000\r\n");
    uart_puts("[stage0] hartid = ");
    uart_puthex(hartid);
    uart_puts("\r\n[stage0] DTB    = ");
    uart_puthex(dtb);

    if (dtb != 0) {
        u32 magic   = *(volatile u32 *)dtb;
        u32 totalsz = *(volatile u32 *)(dtb + 4);
        /* FDT magic 是大端 0xd00dfeed，小端读出来应为 0xedfe0dd0 */
        uart_puts("\r\n[stage0] FDT magic (raw LE) = ");
        uart_puthex(magic);
        uart_puts("\r\n[stage0] FDT totalsize (raw LE) = ");
        uart_puthex(totalsz);
    }

    uart_puts("\r\n[stage0] handoff -> OpenSBI fw_jump @0x80200000");
    uart_puts("\r\n[stage0] a0(hartid)=");
    uart_puthex(hartid);
    uart_puts(" a1(dtb)=");
    uart_puthex(dtb);
    uart_puts("\r\n[stage0] ================================================\r\n");
}

// stage1.c —— 自写 S-mode payload：通过 SBI ecall 打印，验证“OpenSBI 已经就位”
// 注意 SBI 调用约定：a7=EID, a6=FID, a0..a2 入参；返回时 a0=错误码, a1=返回值
typedef unsigned long u64;
typedef unsigned char u8;

#define SBI_EXT_BASE  0x10UL
#define SBI_EXT_DBCN  0x4442434EUL
#define SBI_EXT_LEGACY_CONSOLE_PUTCHAR 0x01UL

static int legacy_fallback = 0;

static long sbi_ecall(u64 ext, u64 fid, u64 a0, u64 a1, u64 a2, long *err)
{
    register u64 r_a0 asm("a0") = a0;
    register u64 r_a1 asm("a1") = a1;
    register u64 r_a2 asm("a2") = a2;
    register u64 r_a6 asm("a6") = fid;
    register u64 r_a7 asm("a7") = ext;
    asm volatile("ecall"
                 : "+r"(r_a0), "+r"(r_a1)
                 : "r"(r_a2), "r"(r_a6), "r"(r_a7)
                 : "memory");
    if (err)
        *err = (long)r_a0;
    return (long)r_a1;
}

static void sbi_putc(char c)
{
    long err = 0;
    if (legacy_fallback) {
        sbi_ecall(SBI_EXT_LEGACY_CONSOLE_PUTCHAR, 0, (u64)c, 0, 0, 0);
        return;
    }
    /* DBCN: fid=0 write, a0=len, a1=buf */
    sbi_ecall(SBI_EXT_DBCN, 0, 1, (u64)&c, 0, &err);
    if (err < 0) {
        legacy_fallback = 1;
        sbi_ecall(SBI_EXT_LEGACY_CONSOLE_PUTCHAR, 0, (u64)c, 0, 0, 0);
    }
}

static void sbi_puts(const char *s)
{
    while (*s)
        sbi_putc(*s++);
}

static void sbi_puthex(u64 v)
{
    static const char hex[] = "0123456789abcdef";
    char buf[16];
    int i;
    for (i = 15; i >= 0; i--) {
        buf[i] = hex[v & 0xf];
        v >>= 4;
    }
    sbi_puts("0x");
    for (i = 0; i < 16; i++)
        sbi_putc(buf[i]);
}

void s_mode_main(void)
{
    long err = 0;
    long ver  = sbi_ecall(SBI_EXT_BASE, 0, 0, 0, 0, &err);   /* get spec version */
    long impl = sbi_ecall(SBI_EXT_BASE, 1, 0, 0, 0, &err);   /* get impl id      */
    long mver = sbi_ecall(SBI_EXT_BASE, 2, 0, 0, 0, &err);   /* get impl version */

    sbi_puts("\r\n");
    sbi_puts("[stage1] ================================================\r\n");
    sbi_puts("[stage1] self-written S-mode payload @0x80400000\r\n");
    sbi_puts("[stage1] this proves OpenSBI is already running (SBI ecall works)\r\n");
    sbi_puts("[stage1] SBI spec version = ");
    sbi_puthex((u64)ver);
    sbi_puts("\r\n[stage1] SBI impl id      = ");
    sbi_puthex((u64)impl);
    sbi_puts("\r\n[stage1] SBI impl version = ");
    sbi_puthex((u64)mver);
    sbi_puts("\r\n[stage1] chain: QEMU reset -> stage0(M,0x80000000) -> OpenSBI(0x80200000) -> stage1(S,0x80400000)\r\n");
    sbi_puts("[stage1] ================================================\r\n");
    sbi_puts("[stage1] now looping (wfi) —— 按 Ctrl-A X 或 timeout 结束 QEMU\r\n");
}

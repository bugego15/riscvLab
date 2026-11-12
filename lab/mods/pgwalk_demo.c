// pgwalk_demo.c —— 自包含页表 walk：读 satp，按 Sv39/Sv48/Sv57 动态解码逐级表项
// 不依赖 RISC-V 未导出的 p4d_offset/pud_offset 等符号，直接按 PTE 格式解码物理页表
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gfp.h>
#include <linux/mm.h>
#include <linux/sched.h>
#include <asm/csr.h>
#include <asm/page.h>

/* RISC-V 64-bit PTE 位域 */
#define PTE_V		(1UL << 0)
#define PTE_R		(1UL << 1)
#define PTE_W		(1UL << 2)
#define PTE_X		(1UL << 3)
#define PTE_U		(1UL << 4)
#define PTE_G		(1UL << 5)
#define PTE_A		(1UL << 6)
#define PTE_D		(1UL << 7)
#define PTE_PPN_MASK	((1UL << 44) - 1)	/* Sv39/48/57 的 PPN 都是 44 bit */

static const char *mode_name(unsigned long mode)
{
	switch (mode) {
	case 0:  return "BARE";
	case 8:  return "Sv39";
	case 9:  return "Sv48";
	case 10: return "Sv57";
	default: return "unknown";
	}
}

static void walk_va(const char *tag, unsigned long va)
{
	unsigned long satp = csr_read(CSR_SATP);
	unsigned long mode = satp >> 60;
	unsigned long shift, levels, table_phys;
	int level = 0;

	if (mode == 0) {
		pr_info("pgwalk: %s: satp=0 (BARE, no paging)\n", tag);
		return;
	}
	/* 顶层 shift：Sv39=30, Sv48=39, Sv57=48；每级 9 bit */
	shift = (mode == 8) ? 30 : (mode == 9) ? 39 : 48;
	levels = (shift - PAGE_SHIFT) / 9 + 1;
	table_phys = (satp & PTE_PPN_MASK) << PAGE_SHIFT;

	pr_info("pgwalk: %s va=%016lx mode=%s(%lu) levels=%lu root_phys=%016lx\n",
		tag, va, mode_name(mode), mode, levels, table_phys);

	for (;;) {
		unsigned long idx = (va >> shift) & 0x1ff;
		unsigned long entry =
			((unsigned long *)__va(table_phys))[idx];

		pr_info("pgwalk:   L%lu shift=%2lu idx=%3lu entry=%016lx%s\n",
			levels - 1 - level, shift, idx, entry,
			(entry & PTE_V) ? "" : "  (INVALID)");
		if (!(entry & PTE_V))
			return;

		if (entry & (PTE_R | PTE_W | PTE_X)) {	/* 叶子项 */
			unsigned long phys = ((entry >> 10) << PAGE_SHIFT) |
					     (va & ((1UL << shift) - 1));
			pr_info("pgwalk:   => LEAF L%lu phys=%016lx flags=%s%s%s%s%s%s%s\n",
				levels - 1 - level, phys,
				(entry & PTE_R) ? "R" : "-",
				(entry & PTE_W) ? "W" : "-",
				(entry & PTE_X) ? "X" : "-",
				(entry & PTE_U) ? "U" : "-",
				(entry & PTE_G) ? "G" : "-",
				(entry & PTE_A) ? "A" : "-",
				(entry & PTE_D) ? "D" : "-");
			return;
		}

		table_phys = (entry >> 10) << PAGE_SHIFT;
		if (shift < 9 + PAGE_SHIFT) {
			pr_info("pgwalk:   unexpected depth\n");
			return;
		}
		shift -= 9;
		level++;
		if (level >= 5)
			return;
	}
}

static int __init pgwalk_demo_init(void)
{
	unsigned long satp = csr_read(CSR_SATP);
	struct mm_struct *mm = current->mm;
	struct page *p;

	pr_info("===== M3 pgwalk_demo: BEGIN =====\n");
	pr_info("pgwalk: satp=%016lx mode=%s asid=%lu root_ppn=%lx\n",
		satp, mode_name(satp >> 60), (satp >> 44) & 0xffff,
		satp & PTE_PPN_MASK);
	pr_info("pgwalk: current comm=%s pid=%d mm=%px mm->pgd=%px __pa(mm->pgd)=%016lx\n",
		current->comm, task_pid_nr(current), mm, mm ? mm->pgd : NULL,
		mm ? (unsigned long)__pa(mm->pgd) : 0);

	if (mm) {
		walk_va("user start_code", mm->start_code);
		walk_va("user start_stack", mm->start_stack);
	}
	walk_va("kernel module text", (unsigned long)&pgwalk_demo_init);

	p = alloc_pages(GFP_KERNEL, 0);
	if (p) {
		walk_va("kernel direct map", (unsigned long)page_to_virt(p));
		__free_pages(p, 0);
	}
	pr_info("===== M3 pgwalk_demo: END =====\n");
	return 0;
}

static void __exit pgwalk_demo_exit(void)
{
	pr_info("pgwalk_demo: unloaded\n");
}

module_init(pgwalk_demo_init);
module_exit(pgwalk_demo_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("RISC-V lab: self-contained page table walk");

// buddy_demo.c —— 观察 buddy 分配器：按 order 逐级分配连续页，记录 pfn/物理地址
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/gfp.h>
#include <linux/mm.h>

#define MAX_TEST_ORDER 9
static struct page *pages[MAX_TEST_ORDER + 1];

static int __init buddy_demo_init(void)
{
	int order;

	pr_info("===== M3 buddy_demo: BEGIN =====\n");
	pr_info("buddy_demo: MAX_PAGE_ORDER=%d, PAGE_SIZE=%lu\n", MAX_PAGE_ORDER, PAGE_SIZE);

	for (order = 0; order <= MAX_TEST_ORDER; order++) {
		struct page *p = alloc_pages(GFP_KERNEL, order);
		phys_addr_t pa;

		if (!p) {
			pr_info("buddy_demo: alloc_pages(order=%d) FAILED (no contiguous block)\n",
				order);
			continue;
		}
		pages[order] = p;
		pa = page_to_phys(p);
		pr_info("buddy_demo: alloc_pages(order=%d) ok page=%px pfn=%lx phys=%pa size=%luKiB\n",
			order, p, page_to_pfn(p), &pa,
			(unsigned long)(PAGE_SIZE << order) / 1024);
	}
	pr_info("buddy_demo: allocations are held now -> userspace reads /proc/buddyinfo\n");
	pr_info("===== M3 buddy_demo: ALLOC DONE =====\n");
	return 0;
}

static void __exit buddy_demo_exit(void)
{
	int order;

	for (order = MAX_TEST_ORDER; order >= 0; order--) {
		if (pages[order]) {
			__free_pages(pages[order], order);
			pages[order] = NULL;
		}
	}
	pr_info("===== M3 buddy_demo: freed all, unloaded =====\n");
}

module_init(buddy_demo_init);
module_exit(buddy_demo_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("RISC-V lab: buddy allocator observation");

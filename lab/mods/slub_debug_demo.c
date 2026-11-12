// slub_debug_demo.c —— 故意越界写，配合内核 boot 参数 slub_debug=FZ 观察 SLUB 红区检测
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/string.h>

static int __init slub_debug_demo_init(void)
{
	char *p = kmalloc(32, GFP_KERNEL);

	if (!p)
		return -ENOMEM;

	pr_info("slub_debug_demo: kmalloc(32) = %px\n", p);
	pr_info("slub_debug_demo: intentionally writing 64 bytes into a 32-byte object\n");
	memset(p, 0x41, 64);
	pr_info("slub_debug_demo: overflow done (redzone overwritten); kfree() now -> expect SLUB report\n");
	kfree(p);
	pr_info("slub_debug_demo: kfree() returned\n");
	return 0;
}

static void __exit slub_debug_demo_exit(void)
{
	pr_info("slub_debug_demo: unloaded\n");
}

module_init(slub_debug_demo_init);
module_exit(slub_debug_demo_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("RISC-V lab: SLUB redzone overflow detection demo");

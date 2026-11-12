// slab_demo.c —— 观察 SLUB：创建自定义 cache + 不同大小 kmalloc，对应 /proc/slabinfo 的 cache
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/string.h>

#define NOBJ 8
static struct kmem_cache *lab_cache;
static void *objs[NOBJ];

/* 有 ctor 的 cache 不会被 SLUB 合并，保证它单独出现在 /proc/slabinfo */
static void lab_ctor(void *p)
{
	memset(p, 0, 64);
}

static const size_t km_sizes[] = { 8, 32, 64, 1024, 4096, 8192 };
#define NKM (sizeof(km_sizes) / sizeof(km_sizes[0]))
static void *km[NKM];

static int __init slab_demo_init(void)
{
	int i;

	pr_info("===== M3 slab_demo: BEGIN =====\n");

	lab_cache = kmem_cache_create("lab_cache", 64, 8, 0, lab_ctor);
	if (!lab_cache) {
		pr_err("slab_demo: kmem_cache_create failed\n");
		return -ENOMEM;
	}
	pr_info("slab_demo: kmem_cache_create(\"lab_cache\", size=64, align=8, ctor) ok\n");

	for (i = 0; i < NOBJ; i++) {
		objs[i] = kmem_cache_alloc(lab_cache, GFP_KERNEL);
		pr_info("slab_demo: kmem_cache_alloc lab_cache[%d] = %px\n", i, objs[i]);
	}
	for (i = 0; i < (int)NKM; i++) {
		km[i] = kmalloc(km_sizes[i], GFP_KERNEL);
		pr_info("slab_demo: kmalloc(%zu) = %px\n", km_sizes[i], km[i]);
	}
	pr_info("slab_demo: allocations held -> userspace reads /proc/slabinfo\n");
	pr_info("===== M3 slab_demo: ALLOC DONE =====\n");
	return 0;
}

static void __exit slab_demo_exit(void)
{
	int i;

	for (i = 0; i < (int)NKM; i++)
		kfree(km[i]);
	for (i = 0; i < NOBJ; i++)
		kmem_cache_free(lab_cache, objs[i]);
	kmem_cache_destroy(lab_cache);
	pr_info("===== M3 slab_demo: freed all, unloaded =====\n");
}

module_init(slab_demo_init);
module_exit(slab_demo_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("RISC-V lab: SLUB allocator observation");

// task_walk.c —— 遍历 task_struct 链表，观察 PID 1 / kthreadd / 内核线程 / 用户进程
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/mm.h>

static int __init task_walk_init(void)
{
	struct task_struct *p, *t;
	int n = 0;

	pr_info("===== M4 task_walk: BEGIN =====\n");
	pr_info("task_walk: init_task=%px init_task.pid=%d\n",
		&init_task, init_task.pid);

	rcu_read_lock();
	for_each_process_thread(p, t) {
		if (n >= 24) {
			pr_info("task_walk: ... truncated at 24 entries\n");
			goto out;
		}
		pr_info("task_walk: [%2d] task=%px pid=%d tgid=%d comm=%-16s state=%u mm=%px stack=%px\n",
			n, t, task_pid_nr(t), task_tgid_nr(t), t->comm,
			READ_ONCE(t->__state), t->mm, t->stack);
		n++;
	}
out:
	rcu_read_unlock();

	pr_info("task_walk: current=%px pid=%d comm=%s flags=0x%x\n",
		current, task_pid_nr(current), current->comm, current->flags);
	pr_info("===== M4 task_walk: END =====\n");
	return 0;
}

static void __exit task_walk_exit(void)
{
	pr_info("task_walk: unloaded\n");
}

module_init(task_walk_init);
module_exit(task_walk_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("RISC-V lab: task_struct walk");

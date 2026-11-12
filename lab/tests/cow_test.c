/* cow_test.c —— fork 写时复制（COW）实验：用 /proc/self/smaps_rollup 观察内存页属性变化 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>

static void print_rollup(const char *tag)
{
	FILE *f = fopen("/proc/self/smaps_rollup", "r");
	char line[256];

	printf("[cow_test] %s /proc/self/smaps_rollup:\n", tag);
	if (!f) {
		perror("smaps_rollup");
		return;
	}
	while (fgets(line, sizeof(line), f)) {
		if (strstr(line, "Rss") || strstr(line, "Shared_Clean") ||
		    strstr(line, "Private_Clean") || strstr(line, "Private_Dirty") ||
		    strstr(line, "Anonymous"))
			printf("  %s", line);
	}
	fclose(f);
}

int main(void)
{
	size_t sz = 4096 * 4;
	char *p;
	pid_t pid;
	int status;

	p = mmap(NULL, sz, PROT_READ | PROT_WRITE,
		 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	memset(p, 'A', sz);
	printf("[cow_test] mapped %zu bytes at %p, touched all pages\n", sz, p);
	print_rollup("before-fork");

	pid = fork();
	if (pid < 0) {
		perror("fork");
		return 1;
	}
	if (pid == 0) {
		printf("[cow_test] child pid=%d writes p[0]='B' (triggers COW)\n",
		       getpid());
		p[0] = 'B';
		printf("[cow_test] child sees p[0]=%c, exiting\n", p[0]);
		print_rollup("child-after-cow");
		_exit(0);
	}

	waitpid(pid, &status, 0);
	printf("[cow_test] parent after child exit: p[0]=%c (child's write must not leak)\n",
	       p[0]);
	print_rollup("after-child-cow");
	munmap(p, sz);
	return 0;
}

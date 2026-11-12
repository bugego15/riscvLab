/* fork_exec.c —— fork / exec / wait 最小实验（静态编译，在 lab initramfs 中运行） */
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>
#include <stdlib.h>

int main(void)
{
	pid_t pid;
	int status;

	printf("[fork_exec] parent pid=%d ppid=%d\n", getpid(), getppid());

	pid = fork();
	if (pid < 0) {
		perror("fork");
		return 1;
	}
	if (pid == 0) {
		printf("[fork_exec] child  pid=%d ppid=%d (after fork)\n",
		       getpid(), getppid());
		execl("/bin/echo", "echo", "[fork_exec] exec /bin/echo OK", (char *)NULL);
		perror("execl");
		_exit(127);
	}

	if (waitpid(pid, &status, 0) < 0) {
		perror("waitpid");
		return 1;
	}
	printf("[fork_exec] parent: child %d exited, status=0x%x (exit=%d)\n",
	       pid, status, WIFEXITED(status) ? WEXITSTATUS(status) : -1);
	return 0;
}

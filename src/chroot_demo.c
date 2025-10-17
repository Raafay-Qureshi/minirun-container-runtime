#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sched.h>

int child_function(void *arg);

int main() {
    printf("Parent: Creating child with new root filesystem\n");

    pid_t child_pid = clone(
        child_function,
        malloc(1024*1024) + 1024*1024,
        CLONE_NEWPID | SIGCHLD,
        NULL
    );

    if (child_pid == -1) {
        perror("clone failed");
        return 1;
    }

    waitpid(child_pid, NULL, 0);
    printf("Parent: Child finished\n");

    return 0;
}

int child_function(void *arg) {
    printf("Child: About to change root to /home/raafayqureshi/container-project/myroot\n");

    if (chroot("/home/raafayqureshi/container-project/myroot") != 0) {
        perror("chroot failed");
        return 1;
    }

    chdir("/");

    printf("Child: Root changed! Let's see what we have here...\n");
    execl("/bin/bash", "bash", NULL);

    return 0;
}
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sched.h>

int child_function(void* arg);

int main() {
    printf("Parent PID: %d\n", getpid());

    pid_t child_pid = clone(child_function, malloc(1024*1024) + 1024*1024, CLONE_NEWPID | SIGCHLD, NULL);

    if (child_pid == -1) {
        perror("clone failed");
        return 1;
    }

    printf("Parent: Created isolated child %d\n", child_pid);
    waitpid(child_pid, NULL, 0);

    return 0;
}

int child_function(void* arg) {
    printf("Child PID (from child's view): %d\n", getpid());
    printf("Child PID (actual): Uses parent's view\n");
    
    execl("/bin/bash", "bash", NULL);
    return 0;
}
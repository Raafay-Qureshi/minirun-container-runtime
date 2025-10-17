#include <stdio.h>
#include <unistd.h>

int main() {
    printf("Parent process: My ID is %d\n", getpid());

    pid_t child_pid = fork();

    if (child_pid == 0) {
        printf("Child process: My ID is %d, my parent is %d\n", getpid(), getppid());
    } else {
        printf("Parent process: I created child with ID %d\n", child_pid);
    }

    return 0;
}
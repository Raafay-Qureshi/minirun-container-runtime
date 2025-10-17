#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

int main() {
    printf("Parent: About to create a child\n");

    pid_t child_pid = fork();

    if (child_pid == 0) {
        // Child
        printf("Child: I'm about to become 'ls'\n");
        execl("/bin/echo", "echo", "Hello from child", NULL);

        // Error: Something went wrong
        printf("Child: exec failed\n");
    } else {
        // Parent
        printf("Parent: Waiting for child %d to finish...\n", child_pid);
        wait(NULL);
        printf("Parent: Child finished!\n");
    }
    return 0;
}
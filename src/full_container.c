#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sched.h>
#include <sys/mount.h>

int child_function(void* arg);

int main() {
    printf("HOST: Creating fully isolated container...\n");
    
    // Create child with BOTH PID and MOUNT namespace
    pid_t child_pid = clone(
        child_function,
        malloc(1024*1024) + 1024*1024,
        CLONE_NEWPID | CLONE_NEWNS | SIGCHLD,  // Added CLONE_NEWNS!
        NULL
    );
    
    if (child_pid == -1) {
        perror("clone failed");
        return 1;
    }
    
    waitpid(child_pid, NULL, 0);
    printf("\nHOST: Container stopped\n");
    
    return 0;
}

int child_function(void* arg) {
    printf("=== CONTAINER STARTING ===\n");
    printf("My PID: %d (should be 1)\n\n", getpid());
    
    // Change root to our fake filesystem
    if (chroot("/home/raafayqureshi/container-project/myroot") != 0) {
        perror("chroot failed");
        return 1;
    }
    chdir("/");
    
    // Mount /proc so 'ps' works
    // /proc is a special filesystem that shows process info
    mount("proc", "/proc", "proc", 0, NULL);
    
    printf("Container ready! Try these commands:\n");
    printf("  ls /          (see limited filesystem)\n");
    printf("  ps aux        (see only container processes)\n");
    printf("  echo $$       (see your PID is 1)\n");
    printf("  exit          (to leave container)\n\n");
    
    // Run bash
    execl("/bin/bash", "bash", NULL);
    
    return 0;
}
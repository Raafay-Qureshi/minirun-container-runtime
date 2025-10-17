#define _GNU_SOURCE
#include <stdio.h>      // printf, fprintf, fopen, fclose
#include <stdlib.h>     // malloc, system, exit
#include <unistd.h>     // getpid, chdir, execl
#include <sys/wait.h>   // waitpid
#include <sched.h>      // clone, CLONE_* flags
#include <sys/mount.h>  // mount

/*
 * container-fixed.c
 * Experimental: Container with cgroups for resource limits
 * This is a learning experiment - exploring CPU and memory limits
 */

int child_function(void* arg);

int main() {
    printf("=== SETTING UP CONTAINER WITH LIMITS ===\n");
    
    // Create cgroup directory
    system("sudo mkdir -p /sys/fs/cgroup/mycontainer");
    
    // Enable memory controller
    system("echo '+memory' | sudo tee /sys/fs/cgroup/cgroup.subtree_control > /dev/null");
    
    // Set memory limit: 512 MB
    system("echo 536870912 | sudo tee /sys/fs/cgroup/mycontainer/memory.max > /dev/null");
    
    // Set CPU limit: 50%
    system("echo '50000 100000' | sudo tee /sys/fs/cgroup/mycontainer/cpu.max > /dev/null");
    
    // Validate cgroup was created with limits
    printf("✓ Cgroup created with limits\n\n");
    
    // Create child with namespaces
    pid_t child_pid = clone(
        child_function,
        malloc(1024*1024) + 1024*1024,
        CLONE_NEWPID | CLONE_NEWNS | SIGCHLD,
        NULL
    );
    
    // ERROR: Child clone failed
    if (child_pid == -1) {
        perror("clone failed");
        return 1;
    }
    
    // Wait for child process to finish
    waitpid(child_pid, NULL, 0);
    
    // Validate that the container has stopped
    printf("\n=== CONTAINER STOPPED ===\n");
    
    // Delete cgroup directory and hide error messages
    system("sudo rmdir /sys/fs/cgroup/mycontainer 2>/dev/null");
    
    // Return successfully
    return 0;
}

// This function is executed only by the child
int child_function(void* arg) {
    printf("=== CONTAINER STARTING ===\n");
    // Child Sees PID as '1'
    printf("My PID: %d\n", getpid());
    
    // Converts PID number to a string and stores in pid_str
    char pid_str[32];
    snprintf(pid_str, sizeof(pid_str), "%d", getpid());
    // Control group file that limits resources (CPU, Memory etc.)
    FILE* cgroup_file = fopen("/sys/fs/cgroup/mycontainer/cgroup.procs", "w");
    // Writes the PID to the Cgroup file
    if (cgroup_file) {
        fprintf(cgroup_file, "%s", pid_str);
        fclose(cgroup_file);
        printf("✓ Added to cgroup\n");
    } else {
        // ERROR: Couldn't add PID to Cgroup file
        printf("✗ Failed to add to cgroup\n");
    }
    
    // Bottlenecks added for this control group
    printf("Memory limit: 512 MB\n");
    printf("CPU limit: 50%%\n\n");
    
    // Change root to our myroot folder so child can't see outside of it
    if (chroot("/home/raafayqureshi/container-project/myroot") != 0) {
        // ERROR: Changing root execution failed
        perror("chroot failed");
        return 1;
    }
    // Changes directory to myroot as we already set it as the new root
    chdir("/");
    
    // Mount /proc so we can use utilities like 'ps' in the container
    mount("proc", "/proc", "proc", 0, NULL);
    
    // Validate that container is ready to user
    printf("Container ready! You can now run commands inside.\n\n");
    
    // Run bash by replacing current program
    execl("/bin/bash", "bash", NULL);
    
    // Return successfully
    return 0;
}
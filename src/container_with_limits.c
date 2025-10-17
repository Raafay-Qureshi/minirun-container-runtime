#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sched.h>
#include <sys/mount.h>
#include <string.h>
#include <fcntl.h>

// Function to write to a cgroup file
void write_cgroup_file(const char* cgroup_path, const char* filename, const char* value) {
    char path[256];
    snprintf(path, sizeof(path), "%s/%s", cgroup_path, filename);
    
    int fd = open(path, O_WRONLY);
    if (fd == -1) {
        perror("Failed to open cgroup file");
        return;
    }
    
    if (write(fd, value, strlen(value)) == -1) {
        perror("Failed to write to cgroup file");
    }
    
    close(fd);
}

int child_function(void* arg) {
    printf("=== CONTAINER STARTING ===\n");
    printf("My PID: %d\n", getpid());
    printf("Memory limit: 512 MB\n");
    printf("CPU limit: 50%%\n\n");
    
    // Change root to our fake filesystem
    if (chroot("/home/raafayqureshi/container-project/myroot") != 0) {
        perror("chroot failed");
        return 1;
    }
    chdir("/");
    
    // Mount /proc
    mount("proc", "/proc", "proc", 0, NULL);
    
    printf("Container ready! Try:\n");
    printf("  cat /proc/self/cgroup   (see your cgroup)\n");
    printf("  exit                    (to leave)\n\n");
    
    // Run bash
    execl("/bin/bash", "bash", NULL);
    
    return 0;
}

int main() {
    char cgroup_path[] = "/sys/fs/cgroup/mycontainer";
    char child_pid_str[32];
    
    printf("=== SETTING UP CONTAINER WITH LIMITS ===\n");
    
    // Create cgroup directory
    system("sudo mkdir -p /sys/fs/cgroup/mycontainer");
    
    // Set memory limit: 512 MB
    system("echo 536870912 | sudo tee /sys/fs/cgroup/mycontainer/memory.max > /dev/null");
    
    // Set CPU limit: 50% (50000 out of 100000 microseconds)
    system("echo '50000 100000' | sudo tee /sys/fs/cgroup/mycontainer/cpu.max > /dev/null");
    
    printf("✓ Memory limit: 512 MB\n");
    printf("✓ CPU limit: 50%%\n");
    printf("✓ Creating isolated container...\n\n");
    
    // Create child with namespaces
    pid_t child_pid = clone(
        child_function,
        malloc(1024*1024) + 1024*1024,
        CLONE_NEWPID | CLONE_NEWNS | SIGCHLD,
        NULL
    );
    
    if (child_pid == -1) {
        perror("clone failed");
        return 1;
    }
    
    // Add child process to cgroup
    snprintf(child_pid_str, sizeof(child_pid_str), "%d", child_pid);
    
    char command[256];
    snprintf(command, sizeof(command), 
             "echo %s | sudo tee /sys/fs/cgroup/mycontainer/cgroup.procs > /dev/null", 
             child_pid_str);
    system(command);
    
    printf("✓ Container PID %d added to cgroup\n", child_pid);
    printf("✓ Resource limits active!\n\n");
    
    // Wait for child
    waitpid(child_pid, NULL, 0);
    
    printf("\n=== CONTAINER STOPPED ===\n");
    
    // Cleanup cgroup
    system("sudo rmdir /sys/fs/cgroup/mycontainer 2>/dev/null");
    
    return 0;
}
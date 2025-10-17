#define _GNU_SOURCE
#include <stdio.h>      // Standard input/output (printf, perror, fprintf)
#include <stdlib.h>     // Standard library (malloc, exit)
#include <unistd.h>     // UNIX standard (getpid, chdir, chroot, execl)
#include <sys/wait.h>   // Wait for child processes (waitpid)
#include <sched.h>      // Scheduling (clone, CLONE_* flags)
#include <sys/mount.h>  // Mounting filesystems (mount)
#include <sys/stat.h>   // File status (mkdir)
#include <errno.h>      // Error numbers (errno)
#include <string.h>     // String operations (strerror)

// Container structure configuration
typedef struct {
    char* name;
    char* rootfs_path;
    char* command;
    long memory_limit;  // in bytes
    int cpu_limit;      // percentage (0-100)
} ContainerConfig;

// Helper function to write to cgroup files with error handling
int write_cgroup_file(const char* path, const char* value);

// Setup and cleanup cgroups
int setup_cgroups(const char* container_name, long memory_limit_bytes, int cpu_percent);
void cleanup_cgroups(const char* container_name);

// Child process function
int child_function(void* arg);

int main(int argc, char* argv[]) {
    // ERROR: Less than 4 arguments, provide user correct instructions
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <name> <rootfs_path> <command>\n", argv[0]);
        fprintf(stderr, "Example: %s myapp /path/to/myroot /bin/bash\n", argv[0]);
        return 1;
    }
    
    // Build config using argument values
    // Default limits: 512MB RAM, 50% CPU
    ContainerConfig config = {
        .name = argv[1],
        .rootfs_path = argv[2],
        .command = argv[3],
        .memory_limit = 512 * 1024 * 1024,   // 512 MB
        .cpu_limit = 50                      // 50%
    };
    
    // Print necessary information
    printf("=== MiniRun Container Runtime ===\n");
    printf("Starting container: %s\n", config.name);
    printf("Root filesystem: %s\n", config.rootfs_path);
    printf("Command: %s\n\n", config.command);
    printf("Limits: %ldMB RAM, %d%% CPU\n\n", 
           config.memory_limit / (1024*1024), config.cpu_limit);
    
    // Setup cgroups before creating container (optional - will warn if fails)
    int cgroups_enabled = setup_cgroups(config.name, config.memory_limit, config.cpu_limit);
    if (!cgroups_enabled) {
        printf("⚠️  WARNING: Running without resource limits\n\n");
    }

    // Allocate stack for child process
    // Note: clone() requires stack pointer to point at TOP of allocated memory
    void* stack = malloc(1024 * 1024);  // 1MB stack
    if (stack == NULL) {
        perror("malloc failed");
        cleanup_cgroups(config.name);
        return 1;
    }

    // Create child with namespaces
    // CLONE_NEWPID: New PID namespace (process will be PID 1)
    // CLONE_NEWNS: New mount namespace (separate filesystem view)
    // SIGCHLD: Send SIGCHLD to parent when child terminates
    pid_t child_pid = clone(
        child_function,
        stack + (1024 * 1024),  // Stack grows downward, point to top
        CLONE_NEWPID | CLONE_NEWNS | SIGCHLD,
        &config
    );
    
    // ERROR: Child clone failed
    if (child_pid == -1) {
        perror("clone failed");
        free(stack);
        cleanup_cgroups(config.name);
        return 1;
    }
    
    // Print Container PID of child
    printf("Container PID: %d\n", child_pid);
    
    // Wait for container to finish
    int status;
    waitpid(child_pid, &status, 0);
    
    // Container has stopped
    printf("\n=== Container [%s] stopped ===\n", config.name);

    // Free the allocated stack memory
    free(stack);
    cleanup_cgroups(config.name);
    
    return 0;
}

/**
 * Helper function: Write to a cgroup file with proper error handling
 *
 * @param path  Full path to cgroup file
 * @param value String value to write
 * @return 0 on success, -1 on failure
 */
int write_cgroup_file(const char* path, const char* value) {
    FILE* f = fopen(path, "w");
    if (f == NULL) {
        // Don't print error here - let caller decide
        return -1;
    }
    
    int ret = fprintf(f, "%s", value);
    fclose(f);
    
    if (ret < 0) {
        return -1;
    }
    
    return 0;
}

/**
 * Setup cgroups for resource limits (memory and CPU)
 *
 * Cgroups v2 structure:
 *   /sys/fs/cgroup/minirun-<name>/
 *     ├── memory.max        (memory limit in bytes)
 *     ├── cpu.max           (CPU quota: "max period" in microseconds)
 *     └── cgroup.procs      (PIDs in this cgroup)
 *
 * @param container_name     Name of container (used for cgroup directory)
 * @param memory_limit_bytes Memory limit in bytes (e.g., 512*1024*1024 for 512MB)
 * @param cpu_percent        CPU percentage (e.g., 50 for 50% of one core)
 * @return 1 if cgroups set up successfully, 0 if failed (container can still run)
 */
int setup_cgroups(const char* container_name, long memory_limit_bytes, int cpu_percent) {
    char cgroup_path[256];
    char file_path[300];  // Slightly larger to fit cgroup_path + filename
    char value[128];
    int success = 1;  // Track if cgroups are working
    
    // Build cgroup directory path: /sys/fs/cgroup/minirun-<name>
    snprintf(cgroup_path, sizeof(cgroup_path), "/sys/fs/cgroup/minirun-%s", container_name);
    
    // Check if cgroups v2 is available
    if (access("/sys/fs/cgroup/cgroup.controllers", F_OK) != 0) {
        fprintf(stderr, "⚠️  Cgroups v2 not available on this system\n");
        fprintf(stderr, "   Container will run without resource limits\n");
        return 0;
    }
    
    // Create cgroup directory
    if (mkdir(cgroup_path, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "⚠️  Failed to create cgroup directory: %s\n", strerror(errno));
        fprintf(stderr, "   Try running with sudo or check permissions\n");
        return 0;
    }
    
    // Enable controllers in parent cgroup (may already be enabled, that's fine)
    // This is needed before child cgroups can use these controllers
    if (write_cgroup_file("/sys/fs/cgroup/cgroup.subtree_control", "+cpu +memory") != 0) {
        // This might fail if already enabled or if we lack permissions - not critical
        // We'll try to set limits anyway
    }
    
    // Set memory limit
    snprintf(file_path, sizeof(file_path), "%s/memory.max", cgroup_path);
    snprintf(value, sizeof(value), "%ld", memory_limit_bytes);
    
    if (write_cgroup_file(file_path, value) != 0) {
        fprintf(stderr, "⚠️  Failed to set memory limit: %s\n", strerror(errno));
        fprintf(stderr, "   Check if memory controller is enabled\n");
        success = 0;
    }
    
    // Set CPU limit
    // Format: "$MAX $PERIOD" (both in microseconds)
    // Example: 50% CPU = "50000 100000" (50ms out of every 100ms)
    long cpu_max = (cpu_percent * 1000);     // Convert percentage to microseconds
    long cpu_period = 100000;                 // 100ms period (standard)
    
    snprintf(file_path, sizeof(file_path), "%s/cpu.max", cgroup_path);
    snprintf(value, sizeof(value), "%ld %ld", cpu_max, cpu_period);
    
    if (write_cgroup_file(file_path, value) != 0) {
        fprintf(stderr, "⚠️  Failed to set CPU limit: %s\n", strerror(errno));
        fprintf(stderr, "   Check if CPU controller is enabled\n");
        success = 0;
    }
    
    // If we successfully set limits, print confirmation
    if (success) {
        printf("✓ Resource limits configured:\n");
        printf("  - Memory: %ldMB\n", memory_limit_bytes / (1024*1024));
        printf("  - CPU: %d%% of one core\n", cpu_percent);
        printf("  - Cgroup: %s\n\n", cgroup_path);
    }
    
    return success;
}

/**
 * Cleanup cgroups after container stops
 *
 * Removes the cgroup directory. This will fail if processes are still in the cgroup,
 * which is fine - kernel will clean up when all processes exit.
 *
 * @param container_name Name of container
 */
void cleanup_cgroups(const char* container_name) {
    char cgroup_path[512];
    
    snprintf(cgroup_path, sizeof(cgroup_path), "/sys/fs/cgroup/minirun-%s", container_name);
    
    // Try to remove cgroup directory
    // This may fail if processes still exist in the cgroup, which is okay
    if (rmdir(cgroup_path) != 0 && errno != ENOENT) {
        // ENOENT means directory doesn't exist (already cleaned up or never created)
        // Other errors we can ignore - kernel will clean up eventually
    }
}

// This function is executed only by the child
// Clone() requires 'void *arg' signature
int child_function(void* arg) {
    ContainerConfig* config = (ContainerConfig*)arg;
    
    // Print Container Name and PID (1 from child's perspective)
    printf("Container [%s] starting...\n", config->name);
    printf("PID: %d\n", getpid());

    // Join the cgroup to apply resource limits
    // We write our PID to cgroup.procs, which moves this process into the cgroup
    char cgroup_procs_path[300];
    char pid_str[32];
    
    snprintf(cgroup_procs_path, sizeof(cgroup_procs_path),
             "/sys/fs/cgroup/minirun-%s/cgroup.procs", config->name);
    snprintf(pid_str, sizeof(pid_str), "%d", getpid());
    
    // Try to join the cgroup
    FILE* cgroup_file = fopen(cgroup_procs_path, "w");
    if (cgroup_file) {
        if (fprintf(cgroup_file, "%s", pid_str) > 0) {
            printf("✓ Resource limits applied to this container\n");
        } else {
            fprintf(stderr, "⚠️  Warning: Could not write PID to cgroup\n");
        }
        fclose(cgroup_file);
    } else {
        // Cgroup doesn't exist or we lack permissions - container continues without limits
        fprintf(stderr, "⚠️  Warning: Running without resource limits\n");
    }
    
    // Change root to our rootfs_path so child can't see outside of it
    if (chroot(config->rootfs_path) != 0) {
        // ERROR: Changing root execution failed
        perror("chroot failed");
        return 1;
    }
    // Changes directory to myroot as we already set it as the new root
    chdir("/");
    
    // Mount /proc so we can use utilities like 'ps' in the container
    if (mount("proc", "/proc", "proc", 0, NULL) != 0) {
        perror("Warning: mount /proc failed (ps command may not work)");
    }
    
    // Validate that container is ready to user
    printf("Container ready! You can now run commands inside.\n\n");
    
    // Run bash by replacing current program
    execl("/bin/bash", "bash", "-c", config->command, NULL);
    
    // ERROR: execution failed
    perror("exec failed");
    return 1;
}
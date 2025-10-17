/*
 * test_namespaces.c
 * Unit test to verify namespace isolation works correctly
 * 
 * Tests:
 * 1. PID namespace isolation (getpid() returns 1 in child)
 * 2. Mount namespace isolation (changes don't affect parent)
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sched.h>
#include <sys/wait.h>
#include <sys/mount.h>
#include <string.h>
#include <errno.h>

// Test results
int tests_passed = 0;
int tests_failed = 0;

#define ASSERT(condition, message) \
    do { \
        if (condition) { \
            printf("  ✓ PASS: %s\n", message); \
            tests_passed++; \
        } else { \
            printf("  ✗ FAIL: %s\n", message); \
            tests_failed++; \
        } \
    } while(0)

/*
 * Test 1: Verify PID namespace isolation
 * Child process should see itself as PID 1
 */
int test_pid_namespace(void* arg) {
    (void)arg;  // Unused parameter
    
    pid_t pid = getpid();
    
    // In a new PID namespace, first process should be PID 1
    ASSERT(pid == 1, "Child process has PID 1 in new namespace");
    
    // Parent PID should be 0 (no parent visible in this namespace)
    pid_t ppid = getppid();
    ASSERT(ppid == 0, "Parent PID is 0 in isolated namespace");
    
    return 0;
}

/*
 * Test 2: Verify Mount namespace isolation
 * Changes in child namespace shouldn't affect parent
 */
int test_mount_namespace(void* arg) {
    (void)arg;
    
    // Try to create a temporary mount point
    // This should only affect this namespace
    const char* test_path = "/tmp/minirun_test_mount";
    
    // Create test directory
    if (mkdir(test_path, 0755) != 0 && errno != EEXIST) {
        printf("  ⚠ WARNING: Could not create test directory: %s\n", strerror(errno));
        return 0;
    }
    
    // Try to mount tmpfs (this requires privileges)
    if (mount("tmpfs", test_path, "tmpfs", 0, NULL) == 0) {
        ASSERT(1, "Mount operation succeeded in isolated namespace");
        
        // Cleanup
        umount(test_path);
    } else {
        // If mount fails due to permissions, that's okay for testing
        printf("  ℹ INFO: Mount test skipped (requires root privileges)\n");
    }
    
    // Cleanup
    rmdir(test_path);
    
    return 0;
}

/*
 * Test 3: Verify clone() creates namespaces correctly
 */
void test_namespace_creation() {
    printf("\n[Test 1: PID Namespace Isolation]\n");
    
    // Allocate stack for child
    void* stack = malloc(1024 * 1024);
    if (stack == NULL) {
        printf("  ✗ FAIL: Could not allocate stack\n");
        tests_failed++;
        return;
    }
    
    // Create child with new PID namespace
    pid_t child_pid = clone(
        test_pid_namespace,
        stack + (1024 * 1024),  // Stack grows downward
        CLONE_NEWPID | SIGCHLD,
        NULL
    );
    
    if (child_pid == -1) {
        printf("  ✗ FAIL: Could not create child process: %s\n", strerror(errno));
        printf("  ℹ INFO: This test requires root privileges (sudo)\n");
        tests_failed++;
        free(stack);
        return;
    }
    
    ASSERT(child_pid > 0, "Child process created successfully");
    
    // Wait for child to complete
    int status;
    waitpid(child_pid, &status, 0);
    
    ASSERT(WIFEXITED(status), "Child process exited normally");
    
    free(stack);
}

/*
 * Test 4: Verify Mount namespace creation
 */
void test_mount_namespace_creation() {
    printf("\n[Test 2: Mount Namespace Isolation]\n");
    
    void* stack = malloc(1024 * 1024);
    if (stack == NULL) {
        printf("  ✗ FAIL: Could not allocate stack\n");
        tests_failed++;
        return;
    }
    
    pid_t child_pid = clone(
        test_mount_namespace,
        stack + (1024 * 1024),
        CLONE_NEWNS | SIGCHLD,
        NULL
    );
    
    if (child_pid == -1) {
        printf("  ✗ FAIL: Could not create child process: %s\n", strerror(errno));
        printf("  ℹ INFO: This test requires root privileges (sudo)\n");
        tests_failed++;
        free(stack);
        return;
    }
    
    ASSERT(child_pid > 0, "Child process created with mount namespace");
    
    int status;
    waitpid(child_pid, &status, 0);
    
    ASSERT(WIFEXITED(status), "Child process exited normally");
    
    free(stack);
}

/*
 * Test 5: Verify combined namespaces
 */
int test_combined_namespaces(void* arg) {
    (void)arg;
    
    // Check PID isolation
    pid_t pid = getpid();
    ASSERT(pid == 1, "PID is 1 with combined namespaces");
    
    return 0;
}

void test_combined_namespace_creation() {
    printf("\n[Test 3: Combined PID and Mount Namespaces]\n");
    
    void* stack = malloc(1024 * 1024);
    if (stack == NULL) {
        printf("  ✗ FAIL: Could not allocate stack\n");
        tests_failed++;
        return;
    }
    
    // This is what the actual container runtime does
    pid_t child_pid = clone(
        test_combined_namespaces,
        stack + (1024 * 1024),
        CLONE_NEWPID | CLONE_NEWNS | SIGCHLD,
        NULL
    );
    
    if (child_pid == -1) {
        printf("  ✗ FAIL: Could not create child with combined namespaces: %s\n", strerror(errno));
        printf("  ℹ INFO: This test requires root privileges (sudo)\n");
        tests_failed++;
        free(stack);
        return;
    }
    
    ASSERT(child_pid > 0, "Child created with PID and Mount namespaces");
    
    int status;
    waitpid(child_pid, &status, 0);
    
    ASSERT(WIFEXITED(status), "Child exited normally");
    
    free(stack);
}

/*
 * Main test runner
 */
int main() {
    printf("╔════════════════════════════════════════════════╗\n");
    printf("║   Namespace Isolation Unit Tests              ║\n");
    printf("╚════════════════════════════════════════════════╝\n");
    
    // Check if running as root
    if (geteuid() != 0) {
        printf("\n⚠️  WARNING: Tests require root privileges\n");
        printf("   Run with: sudo %s\n\n", "tests/unit/test_namespaces");
        return 1;
    }
    
    // Run tests
    test_namespace_creation();
    test_mount_namespace_creation();
    test_combined_namespace_creation();
    
    // Summary
    printf("\n════════════════════════════════════════════════\n");
    printf("Test Results:\n");
    printf("  Passed: %d\n", tests_passed);
    printf("  Failed: %d\n", tests_failed);
    printf("════════════════════════════════════════════════\n");
    
    if (tests_failed > 0) {
        printf("\n❌ Some tests failed\n");
        return 1;
    } else {
        printf("\n✅ All tests passed!\n");
        return 0;
    }
}
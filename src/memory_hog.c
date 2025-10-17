#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    printf("Starting memory hog...\n");
    printf("I'm going to try to allocate 1GB of RAM!\n");
    
    int allocated_mb = 0;
    
    while(1) {
        // Allocate 10MB at a time
        char* memory = malloc(10 * 1024 * 1024);
        
        if (memory == NULL) {
            printf("Allocation failed at %d MB\n", allocated_mb);
            break;
        }
        
        // Actually use the memory (otherwise Linux won't really allocate it)
        for (int i = 0; i < 10 * 1024 * 1024; i++) {
            memory[i] = 1;
        }
        
        allocated_mb += 10;
        printf("Allocated: %d MB\n", allocated_mb);
        sleep(1);  // Slow it down so we can watch
    }
    
    return 0;
}
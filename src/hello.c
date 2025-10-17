#include <stdio.h>

int main() {
    printf("hello from process %d\n", getpid());
    return;
}
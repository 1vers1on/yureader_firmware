#include <zephyr/kernel.h>

int main(void) {
    volatile int alive = 0;

    while (1) {
        alive++;
        __asm volatile ("nop");
    }
}

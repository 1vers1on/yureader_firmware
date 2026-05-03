#include <zephyr/kernel.h>

extern void zig_main(void);

int main(void) {
    zig_main();
    return 0;
}

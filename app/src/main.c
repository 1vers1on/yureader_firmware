#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

int main(void) {
    LOG_INF("Starting YuReader...");

    while (1) {
        LOG_INF("loop");
        k_sleep(K_SECONDS(1));
    }

    return 0;
}

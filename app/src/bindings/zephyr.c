#include <stdint.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

#define export __attribute__((visibility("default")))

export void *zig_k_malloc(size_t size) {
    return k_malloc(size);
}

export void zig_k_free(void *ptr) {
    k_free(ptr);
}

export void *zig_k_calloc(size_t nmemb, size_t size) {
    return k_calloc(nmemb, size);
}

export void *zig_k_realloc(void *ptr, size_t size) {
    return k_realloc(ptr, size);
}

export void zig_k_msleep(int32_t ms) {
    (void)k_msleep(ms);
}

export void zig_printk_str(const char *s) {
    printk("%s", s);
}

export int64_t zig_k_uptime_get(void) {
    return k_uptime_get();
}

export uint32_t zig_k_cycle_get_32(void) {
    return k_cycle_get_32();
}

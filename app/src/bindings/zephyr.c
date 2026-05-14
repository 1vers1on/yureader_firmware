#include <stdint.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <zephyr/sys/crc.h>

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

export void *zig_k_aligned_alloc(size_t alignment, size_t size) {
    return k_aligned_alloc(alignment, size);
}

export uint32_t zig_crc32_c(uint32_t crc, const void *data, size_t len, bool first_pkt, bool last_pkt) {
    return crc32_c(crc, (const uint8_t *)data, len, first_pkt, last_pkt);
}

/* Convenience: compute CRC32C for a single buffer (no streaming). */
export uint32_t zig_crc32c_single(const void *data, size_t len) {
    return crc32_c(0U, (const uint8_t *)data, len, true, true);
}

export void zig_k_busy_wait(int32_t ms) {
    k_busy_wait(ms * 1000);
}

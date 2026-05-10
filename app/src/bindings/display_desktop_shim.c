#include <stdint.h>
#include <stddef.h>

int zig_display_is_ready() { return 1; }

int zig_display_get_caps(void *caps) {
    if (!caps) return -1;
    // caps is a Zig extern struct layout; fill minimal fields by byte offsets
    // Safer to memset zero and set width/height at offsets 0 and 2
    unsigned char *b = (unsigned char *)caps;
    b[0] = 296 & 0xff;
    b[1] = (296 >> 8) & 0xff;
    b[2] = 128 & 0xff;
    b[3] = (128 >> 8) & 0xff;
    return 0;
}

int zig_display_set_mono01() { return 0; }
int zig_display_set_mono10() { return 0; }
int zig_display_set_blanking_on() { return 0; }
int zig_display_set_blanking_off() { return 0; }

int zig_display_write(uint16_t x, uint16_t y, uint16_t width, uint16_t height, uint16_t pitch, const void *buf, size_t buf_size) {
    (void)x; (void)y; (void)width; (void)height; (void)pitch; (void)buf; (void)buf_size;
    return 0;
}

int zig_display_set_orientation(int orientation) { (void)orientation; return 0; }
int zig_display_clear() { return 0; }

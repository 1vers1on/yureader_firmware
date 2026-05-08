#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/display.h>

#define ZIG_EXPORT __attribute__((visibility("default")))

static const struct device *display_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_display));

struct zig_display_caps {
    uint16_t width;
    uint16_t height;

    uint32_t supported_pixel_formats;
    uint32_t screen_info;

    int current_pixel_format;
    int current_orientation;
};

ZIG_EXPORT int zig_display_is_ready() {
    return device_is_ready(display_dev);
}

ZIG_EXPORT int zig_display_get_caps(struct zig_display_caps *caps) {
    struct display_capabilities display_caps;
    display_get_capabilities(display_dev, &display_caps);

    caps->width = display_caps.x_resolution;
    caps->height = display_caps.y_resolution;
    caps->supported_pixel_formats = display_caps.supported_pixel_formats;
    caps->screen_info = display_caps.screen_info;
    caps->current_pixel_format = display_caps.current_pixel_format;
    caps->current_orientation = display_caps.current_orientation;

    return 0;
}

ZIG_EXPORT int zig_display_set_mono01() {
    int ret = display_set_pixel_format(display_dev, PIXEL_FORMAT_MONO01);
    return ret;
}

ZIG_EXPORT int zig_display_set_mono10() {
    int ret = display_set_pixel_format(display_dev, PIXEL_FORMAT_MONO10);
    return ret;
}

ZIG_EXPORT int zig_display_set_blanking_on() {
    int ret = display_blanking_on(display_dev);
    return ret;
}

ZIG_EXPORT int zig_display_set_blanking_off() {
    int ret = display_blanking_off(display_dev);
    return ret;
}

ZIG_EXPORT int zig_display_write(uint16_t x, uint16_t y, uint16_t width, uint16_t height, uint16_t pitch, const void *buf, size_t buf_size) {
    struct display_buffer_descriptor desc = {
        .width = width,
        .height = height,
        .pitch = pitch,
        .buf_size = buf_size,
    };

    int ret = display_write(display_dev, x, y, &desc, buf);
    return ret;
}

ZIG_EXPORT int zig_display_set_orientation(int orientation) {
    return display_set_orientation(display_dev, (enum display_orientation)orientation);
}

ZIG_EXPORT int zig_display_clear() {
    return display_clear(display_dev);
}

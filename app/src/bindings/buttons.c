#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/sys/atomic.h>

#define ZIG_EXPORT __attribute__((visibility("default")))

#define NUM_BUTTONS 6

static const struct gpio_dt_spec buttons[NUM_BUTTONS] = {
    GPIO_DT_SPEC_GET(DT_ALIAS(sw0), gpios), GPIO_DT_SPEC_GET(DT_ALIAS(sw1), gpios),
    GPIO_DT_SPEC_GET(DT_ALIAS(sw2), gpios), GPIO_DT_SPEC_GET(DT_ALIAS(sw3), gpios),
    GPIO_DT_SPEC_GET(DT_ALIAS(sw4), gpios), GPIO_DT_SPEC_GET(DT_ALIAS(sw5), gpios)};

static struct gpio_callback button_cbs[NUM_BUTTONS];
static struct k_work button_work;

static atomic_t pending_buttons;

extern void zig_button_pressed(uint8_t id);

static void handle_button(uint8_t id) {
    zig_button_pressed(id);
}

static void button_work_handler(struct k_work* work) {
    atomic_val_t pending = atomic_set(&pending_buttons, 0);

    for (uint8_t i = 0; i < NUM_BUTTONS; i++) {
        if (pending & BIT(i)) {
            handle_button(i);
        }
    }
}

static void button_isr(const struct device* port, struct gpio_callback* cb, gpio_port_pins_t pins) {
    ARG_UNUSED(cb);

    for (uint8_t i = 0; i < NUM_BUTTONS; i++) {
        if (buttons[i].port == port && (pins & BIT(buttons[i].pin))) {
            atomic_or(&pending_buttons, BIT(i));
        }
    }

    k_work_submit(&button_work);
}

ZIG_EXPORT int zig_buttons_init(void) {
    int ret;

    k_work_init(&button_work, button_work_handler);

    for (uint8_t i = 0; i < NUM_BUTTONS; i++) {
        if (!gpio_is_ready_dt(&buttons[i])) {
            return -ENODEV;
        }

        ret = gpio_pin_configure_dt(&buttons[i], GPIO_INPUT);
        if (ret < 0) {
            return ret;
        }

        ret = gpio_pin_interrupt_configure_dt(&buttons[i], GPIO_INT_EDGE_TO_ACTIVE);
        if (ret < 0) {
            return ret;
        }

        gpio_init_callback(&button_cbs[i], button_isr, BIT(buttons[i].pin));

        ret = gpio_add_callback(buttons[i].port, &button_cbs[i]);
        if (ret < 0) {
            return ret;
        }
    }

    return 0;
}

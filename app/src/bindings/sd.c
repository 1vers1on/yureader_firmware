#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#include <ff.h>

#include <zephyr/drivers/gpio.h>
#include <zephyr/fs/fs.h>
#include <zephyr/kernel.h>

extern void zig_sd_card_changed(void);

#define ZIG_EXPORT __attribute__((visibility("default")))

#define SD_DISK_NAME "SD"
#define SD_MOUNT_POINT "/SD:"
#define SD_MAX_FILES 8

#define USER_NODE DT_PATH(zephyr_user)

static const struct gpio_dt_spec sd_cd = GPIO_DT_SPEC_GET(USER_NODE, sd_cd_gpios);

static FATFS sd_fatfs;

static struct fs_mount_t sd_mount = {
    .type = FS_FATFS,
    .fs_data = &sd_fatfs,
    .mnt_point = SD_MOUNT_POINT,
};

static struct fs_file_t sd_files[SD_MAX_FILES];
static bool sd_file_in_use[SD_MAX_FILES];

static struct gpio_callback sd_cd_cb;
static struct k_work sd_cd_work;

K_MUTEX_DEFINE(sd_lock);

enum sd_open_mode {
    SD_OPEN_READ = 0,
    SD_OPEN_WRITE_TRUNC = 1,
    SD_OPEN_APPEND = 2,
    SD_OPEN_READ_WRITE = 3,
};

static int sd_validate_fd_locked(int fd) {
    if (fd < 0 || fd >= SD_MAX_FILES) {
        return -EBADF;
    }

    if (!sd_file_in_use[fd]) {
        return -EBADF;
    }

    return 0;
}

static int sd_allocate_file_slot_locked(void) {
    for (int i = 0; i < SD_MAX_FILES; i++) {
        if (!sd_file_in_use[i]) {
            fs_file_t_init(&sd_files[i]);
            sd_file_in_use[i] = true;
            return i;
        }
    }

    return -ENOMEM;
}

static void sd_card_changed_work(struct k_work *work) {
    ARG_UNUSED(work);
    zig_sd_card_changed();
}

static void sd_cd_gpio_callback(
    const struct device *port,
    struct gpio_callback *cb,
    uint32_t pins
) {
    ARG_UNUSED(port);
    ARG_UNUSED(cb);
    ARG_UNUSED(pins);

    k_work_submit(&sd_cd_work);
}

ZIG_EXPORT int zig_sd_cd_init(void) {
    int ret;

    k_mutex_lock(&sd_lock, K_FOREVER);

    if (!gpio_is_ready_dt(&sd_cd)) {
        ret = -ENODEV;
        goto out;
    }

    ret = gpio_pin_configure_dt(&sd_cd, GPIO_INPUT);
    if (ret < 0) {
        goto out;
    }

    k_work_init(&sd_cd_work, sd_card_changed_work);
    gpio_init_callback(&sd_cd_cb, sd_cd_gpio_callback, BIT(sd_cd.pin));

    ret = gpio_add_callback_dt(&sd_cd, &sd_cd_cb);
    if (ret < 0) {
        goto out;
    }

    ret = gpio_pin_interrupt_configure_dt(&sd_cd, GPIO_INT_EDGE_BOTH);
    if (ret < 0) {
        gpio_remove_callback_dt(&sd_cd, &sd_cd_cb);
        goto out;
    }

out:
    k_mutex_unlock(&sd_lock);
    return ret;
}

ZIG_EXPORT int zig_sd_card_present(void) {
    k_mutex_lock(&sd_lock, K_FOREVER);
    int result = gpio_pin_get_dt(&sd_cd);
    k_mutex_unlock(&sd_lock);

    return result;
}

ZIG_EXPORT int zig_sd_mount(void) {
    k_mutex_lock(&sd_lock, K_FOREVER);
    int ret = fs_mount(&sd_mount);
    k_mutex_unlock(&sd_lock);

    return ret;
}

ZIG_EXPORT int zig_sd_unmount(void) {
    k_mutex_lock(&sd_lock, K_FOREVER);
    int ret = fs_unmount(&sd_mount);
    k_mutex_unlock(&sd_lock);

    return ret;
}

ZIG_EXPORT int zig_sd_format(void) {
    MKFS_PARM opt = {
        .fmt = FM_FAT32,
        .n_fat = 0,
        .align = 0,
        .n_root = 0,
        .au_size = 0,
    };

    k_mutex_lock(&sd_lock, K_FOREVER);
    int ret = fs_mkfs(FS_FATFS, (uintptr_t)SD_DISK_NAME, &opt, 0);
    k_mutex_unlock(&sd_lock);

    return ret;
}

ZIG_EXPORT int zig_sd_open_file(const char *path, enum sd_open_mode mode) {
    int ret;
    int flags = 0;

    switch (mode) {
        case SD_OPEN_READ:
            flags = FS_O_READ;
            break;

        case SD_OPEN_WRITE_TRUNC:
            flags = FS_O_CREATE | FS_O_WRITE | FS_O_TRUNC;
            break;

        case SD_OPEN_APPEND:
            flags = FS_O_CREATE | FS_O_WRITE | FS_O_APPEND;
            break;

        case SD_OPEN_READ_WRITE:
            flags = FS_O_CREATE | FS_O_READ | FS_O_WRITE;
            break;

        default:
            return -EINVAL;
    }

    k_mutex_lock(&sd_lock, K_FOREVER);

    int slot = sd_allocate_file_slot_locked();
    if (slot < 0) {
        ret = slot;
        goto out;
    }

    ret = fs_open(&sd_files[slot], path, flags);
    if (ret < 0) {
        sd_file_in_use[slot] = false;
        goto out;
    }

    ret = slot;

out:
    k_mutex_unlock(&sd_lock);
    return ret;
}

ZIG_EXPORT int zig_sd_close_file(int fd) {
    k_mutex_lock(&sd_lock, K_FOREVER);

    int ret = sd_validate_fd_locked(fd);
    if (ret < 0) {
        goto out;
    }

    ret = fs_close(&sd_files[fd]);
    sd_file_in_use[fd] = false;

out:
    k_mutex_unlock(&sd_lock);
    return ret;
}

ZIG_EXPORT ssize_t zig_sd_read_file(int fd, void *buffer, size_t size) {
    k_mutex_lock(&sd_lock, K_FOREVER);

    int ret = sd_validate_fd_locked(fd);
    if (ret < 0) {
        k_mutex_unlock(&sd_lock);
        return ret;
    }

    ssize_t result = fs_read(&sd_files[fd], buffer, size);

    k_mutex_unlock(&sd_lock);
    return result;
}

ZIG_EXPORT ssize_t zig_sd_read_file_len(
    int fd,
    void *buffer,
    size_t offset,
    size_t len
) {
    k_mutex_lock(&sd_lock, K_FOREVER);

    int ret = sd_validate_fd_locked(fd);
    if (ret < 0) {
        k_mutex_unlock(&sd_lock);
        return ret;
    }

    ret = fs_seek(&sd_files[fd], (off_t)offset, FS_SEEK_SET);
    if (ret < 0) {
        k_mutex_unlock(&sd_lock);
        return ret;
    }

    ssize_t result = fs_read(&sd_files[fd], buffer, len);

    k_mutex_unlock(&sd_lock);
    return result;
}

ZIG_EXPORT int zig_sd_seek_file(int fd, off_t offset, int whence) {
    k_mutex_lock(&sd_lock, K_FOREVER);

    int ret = sd_validate_fd_locked(fd);
    if (ret < 0) {
        goto out;
    }

    ret = fs_seek(&sd_files[fd], offset, whence);

out:
    k_mutex_unlock(&sd_lock);
    return ret;
}

ZIG_EXPORT ssize_t zig_sd_write_file(int fd, const void *buffer, size_t size) {
    k_mutex_lock(&sd_lock, K_FOREVER);

    int ret = sd_validate_fd_locked(fd);
    if (ret < 0) {
        k_mutex_unlock(&sd_lock);
        return ret;
    }

    ssize_t result = fs_write(&sd_files[fd], buffer, size);

    k_mutex_unlock(&sd_lock);
    return result;
}

ZIG_EXPORT int zig_sd_mkdir(const char *path) {
    k_mutex_lock(&sd_lock, K_FOREVER);
    int ret = fs_mkdir(path);
    k_mutex_unlock(&sd_lock);

    return ret;
}

ZIG_EXPORT int zig_sd_delete(const char *path) {
    k_mutex_lock(&sd_lock, K_FOREVER);
    int ret = fs_unlink(path);
    k_mutex_unlock(&sd_lock);

    return ret;
}

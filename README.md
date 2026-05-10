# yureader_firmware

Firmware for my yureader project.

## Setup

From the repository root, initialize the West workspace:

```sh
west init -l app
west update
west zephyr-export
```

## Build

From the `app` directory, build for the application board:

```sh
west build --board=yureader/nrf54l15/cpuapp --pristine -- -DBOARD_ROOT=.
```

## Desktop Demo

From `app/src`, build and run the native rendering demo:

```sh
zig build desktop-demo-run
```

That writes PBM images to `desktop-demo-output/`, which you can open on your desktop to inspect the renderer output without flashing hardware.

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

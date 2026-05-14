#!/bin/bash

set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
image_file="$script_dir/build/app/zephyr/zephyr.hex"

pyocd_bin="${PYOCD:-pyocd}"
pyocd_target="nrf54l"
pyocd_freq=1000000

usage() {
    echo "usage: $0 <command>"
    echo
    echo "commands:"
    echo "  flash         flash firmware"
    echo "  reset         reset target"
    echo "  halt          reset and halt"
    echo "  erase         chip erase"
    echo "  recover       recover locked chip"
    echo "  console       open pyocd commander"
    echo "  gdbserver     start pyocd gdb server"
    exit 1
}

flash() {
    exec "$pyocd_bin" flash \
        --frequency "$pyocd_freq" \
        --format hex \
        --target "$pyocd_target" \
        "$image_file"
}

reset() {
    exec "$pyocd_bin" cmd \
        --frequency "$pyocd_freq" \
        --target "$pyocd_target" \
        -c reset
}

halt() {
    exec "$pyocd_bin" cmd \
        --frequency "$pyocd_freq" \
        --target "$pyocd_target" \
        -c "reset halt"
}

erase() {
    exec "$pyocd_bin" erase \
        --frequency "$pyocd_freq" \
        --target "$pyocd_target" \
        --chip
}

recover() {
    exec "$pyocd_bin" cmd \
        --frequency "$pyocd_freq" \
        --target "$pyocd_target" \
        -c unlock
}

console() {
    exec "$pyocd_bin" commander \
        --frequency "$pyocd_freq" \
        --target "$pyocd_target"
}

gdbserver() {
    exec "$pyocd_bin" gdbserver \
        --frequency "$pyocd_freq" \
        --target "$pyocd_target"
}

cmd="${1:-}"

case "$cmd" in
    flash)
        flash
        ;;
    reset)
        reset
        ;;
    halt)
        halt
        ;;
    erase)
        erase
        ;;
    recover)
        recover
        ;;
    console)
        console
        ;;
    gdbserver)
        gdbserver
        ;;
    *)
        usage
        ;;
esac
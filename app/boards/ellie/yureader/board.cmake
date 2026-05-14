board_runner_args(jlink "--device=nRF54L15_M33" "--speed=4000")
board_runner_args(pyocd "--target=nrf54l" "--frequency=1000000")

include(${ZEPHYR_BASE}/boards/common/nrfutil.board.cmake)
include(${ZEPHYR_BASE}/boards/common/jlink.board.cmake)
include(${ZEPHYR_BASE}/boards/common/pyocd.board.cmake)

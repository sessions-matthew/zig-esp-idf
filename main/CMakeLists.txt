# Register ESP-IDF component first (satisfies component_get_requirements phase)
idf_component_register(
    SRCS "app_entry.c"
    INCLUDE_DIRS "."
    REQUIRES esp_driver_gpio esp_driver_uart freertos esp_system esp_timer
)

# ── Zig Core Build and Link ────────────────────────────────────────────────
set(ZIG_PROJECT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(ZIG_OBJ "${ZIG_PROJECT_DIR}/zig-out/lib/zig_esp_idf.o")

find_program(ZIG_EXECUTABLE zig)
if(NOT ZIG_EXECUTABLE)
    message(FATAL_ERROR "Zig 0.17+ executable not found in PATH")
endif()

# Determine architecture flag for Zig based on ESP-IDF target
if(IDF_TARGET STREQUAL "esp32" OR IDF_TARGET STREQUAL "esp32s2" OR IDF_TARGET STREQUAL "esp32s3")
    set(ZIG_ARCH_FLAG "-Darch=xtensa")
else()
    set(ZIG_ARCH_FLAG "-Darch=riscv32")
endif()

# Build the Zig object artifact during CMake generation/build
message(STATUS "Compiling Zig ESP-IDF core object (${IDF_TARGET} -> ${ZIG_ARCH_FLAG})...")
execute_process(
    COMMAND ${ZIG_EXECUTABLE} build app-core --release=small ${ZIG_ARCH_FLAG}
    WORKING_DIRECTORY "${ZIG_PROJECT_DIR}"
    RESULT_VARIABLE zig_res
)
if(NOT zig_res EQUAL 0)
    message(FATAL_ERROR "Failed to build Zig core object via 'zig build app-core ${ZIG_ARCH_FLAG}'")
endif()

if(EXISTS "${ZIG_OBJ}")
    target_sources(${COMPONENT_LIB} PRIVATE "${ZIG_OBJ}")
    message(STATUS "Linked Zig object: ${ZIG_OBJ}")
else()
    message(FATAL_ERROR "Expected Zig object missing at: ${ZIG_OBJ}")
endif()

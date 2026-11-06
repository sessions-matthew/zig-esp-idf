/*
 * app_entry.c — Minimal C anchor for ESP-IDF CMake component registration.
 *
 * The primary application entry point `app_main(void)` and all RTOS/HAL
 * modules are implemented purely in Zig 0.17.0 and linked via
 * zig-out/lib/zig_esp_idf.o.
 */

const char *zig_esp_idf_version(void) {
    return "0.1.0";
}

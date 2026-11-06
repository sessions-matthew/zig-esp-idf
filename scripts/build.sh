#!/usr/bin/env bash
# ============================================================================
# build.sh — Build, test, flash, and monitor Zig FreeRTOS ESP-IDF project.
#
# Usage:
#   ./scripts/build.sh [build]         Build Zig object & ESP-IDF binary
#   ./scripts/build.sh app-core        Build Zig RISC-V object only
#   ./scripts/build.sh test            Run host unit tests (pure Zig, 0 hardware)
#   ./scripts/build.sh flash [port]    Flash to ESP32 over direct USB (auto-detected)
#   ./scripts/build.sh monitor [port]  Open serial console monitor
#   ./scripts/build.sh clean           Clean all build artifacts
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m OK \033[0m %s\n" "$*"; }
err()  { printf "\033[1;31mFAIL\033[0m %s\n" "$*" >&2; exit 1; }

ensure_idf() {
    if ! command -v idf.py >/dev/null 2>&1; then
        local idf_export="${HOME}/esp/esp-idf/export.sh"
        if [[ -f "${idf_export}" ]]; then
            info "Activating ESP-IDF environment from ${idf_export}..."
            # shellcheck source=/dev/null
            source "${idf_export}" >/dev/null 2>&1
        else
            err "ESP-IDF not found. Please ensure idf.py is in PATH or ~/esp/esp-idf/export.sh exists."
        fi
    fi
}

detect_esp_port() {
    local port="${1:-}"
    if [[ -n "${port}" ]]; then
        echo "${port}"
        return 0
    fi
    for candidate in /dev/cu.usbmodem*; do
        if [[ -e "${candidate}" ]]; then
            echo "${candidate}"
            return 0
        fi
    done
    echo ""
}

cmd_test() {
    info "Running host unit tests (Zig 0.17)..."
    (cd "${SCRIPT_DIR}" && zig build test --summary all)
    ok "All unit tests passed!"
}

cmd_app_core() {
    info "Building Zig RISC-V 32 object..."
    (cd "${SCRIPT_DIR}" && zig build app-core)
    ok "Zig object ready: ${SCRIPT_DIR}/zig-out/lib/zig_esp_idf.o"
}

cmd_build() {
    cmd_app_core

    info "Building ESP-IDF application binary..."
    ensure_idf
    (cd "${SCRIPT_DIR}" && idf.py build)
    ok "Firmware build complete: ${SCRIPT_DIR}/build/zig_esp_idf.bin"
}

cmd_flash() {
    local port
    port="$(detect_esp_port "${1:-}")"
    ensure_idf
    if [[ -n "${port}" ]]; then
        info "Flashing to ESP32 over USB (${port})..."
        (cd "${SCRIPT_DIR}" && idf.py -p "${port}" flash)
    else
        info "Flashing to default detected port..."
        (cd "${SCRIPT_DIR}" && idf.py flash)
    fi
    ok "Flash complete!"
}

cmd_monitor() {
    local port
    port="$(detect_esp_port "${1:-}")"
    ensure_idf
    if [[ -n "${port}" ]]; then
        info "Opening serial monitor on ${port}..."
        (cd "${SCRIPT_DIR}" && idf.py -p "${port}" monitor)
    else
        (cd "${SCRIPT_DIR}" && idf.py monitor)
    fi
}

cmd_clean() {
    info "Cleaning build artifacts..."
    rm -rf "${SCRIPT_DIR}/build" "${SCRIPT_DIR}/.zig-cache" "${SCRIPT_DIR}/zig-out"
    ok "Clean complete."
}

# Command dispatch
case "${1:-build}" in
    build)
        cmd_build
        ;;
    app-core)
        cmd_app_core
        ;;
    test)
        cmd_test
        ;;
    flash)
        shift || true
        cmd_flash "${1:-}"
        ;;
    monitor)
        shift || true
        cmd_monitor "${1:-}"
        ;;
    clean)
        cmd_clean
        ;;
    help|--help|-h)
        sed -n '2,13p' "$0"
        ;;
    *)
        err "Unknown command: $1. Run with --help for usage."
        ;;
esac

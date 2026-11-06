//! ESP32 Hardware Abstraction Layer - Silicon Delay & Cycles
//!
//! Provides bare-metal microsecond busy-wait delays via ROM routines,
//! completely independent of FreeRTOS or any operating system.
//! (For OS task scheduling delays, see `rtos.Task.delay` or `rtos.delayMs`).

const std = @import("std");
const builtin = @import("builtin");

extern fn esp_rom_delay_us(us: u32) void;

var mock_elapsed_us: u32 = 0;

fn mock_esp_rom_delay_us(us: u32) callconv(.c) void {
    mock_elapsed_us +%= us;
}

comptime {
    if (builtin.is_test) {
        @export(&mock_esp_rom_delay_us, .{ .name = "esp_rom_delay_us" });
    }
}

/// Busy-wait delay in microseconds using hardware ROM routines
pub inline fn delayUs(us: u32) void {
    if (builtin.is_test) {
        mock_esp_rom_delay_us(us);
    } else {
        esp_rom_delay_us(us);
    }
}

/// Busy-wait delay in milliseconds (loops microsecond ROM delay)
pub fn delayMs(ms: u32) void {
    var remaining = ms;
    while (remaining > 0) : (remaining -= 1) {
        delayUs(1000);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "hardware delay execution in tests" {
    mock_elapsed_us = 0;
    delayUs(50);
    try std.testing.expectEqual(@as(u32, 50), mock_elapsed_us);

    delayMs(2);
    try std.testing.expectEqual(@as(u32, 2050), mock_elapsed_us);
}

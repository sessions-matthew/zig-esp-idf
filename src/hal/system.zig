//! ESP32 Hardware Abstraction Layer - System
//!
//! Provides system-level heap interrogation, uptime, and reset control.

const std = @import("std");
const builtin = @import("builtin");

extern fn esp_get_free_heap_size() u32;
extern fn esp_get_minimum_free_heap_size() u32;
extern fn esp_restart() void;
extern fn esp_timer_get_time() i64;

var mock_free_heap: u32 = 320000;
var mock_min_free_heap: u32 = 300000;
pub var mock_restart_called: bool = false;
pub var mock_uptime_us: i64 = 1_000_000;

fn mock_esp_get_free_heap_size() callconv(.c) u32 {
    return mock_free_heap;
}
fn mock_esp_get_minimum_free_heap_size() callconv(.c) u32 {
    return mock_min_free_heap;
}
fn mock_esp_restart() callconv(.c) void {
    mock_restart_called = true;
}
fn mock_esp_timer_get_time() callconv(.c) i64 {
    return mock_uptime_us;
}

comptime {
    if (builtin.is_test) {
        @export(&mock_esp_get_free_heap_size, .{ .name = "esp_get_free_heap_size" });
        @export(&mock_esp_get_minimum_free_heap_size, .{ .name = "esp_get_minimum_free_heap_size" });
        @export(&mock_esp_restart, .{ .name = "esp_restart" });
        @export(&mock_esp_timer_get_time, .{ .name = "esp_timer_get_time" });
    }
}

pub const System = struct {
    pub fn getFreeHeap() u32 {
        return if (builtin.is_test) mock_esp_get_free_heap_size() else esp_get_free_heap_size();
    }

    pub fn getMinimumFreeHeap() u32 {
        return if (builtin.is_test) mock_esp_get_minimum_free_heap_size() else esp_get_minimum_free_heap_size();
    }

    pub fn restart() void {
        if (builtin.is_test) {
            mock_esp_restart();
        } else {
            esp_restart();
        }
    }

    pub fn getUptimeUs() u64 {
        const t = if (builtin.is_test) mock_esp_timer_get_time() else esp_timer_get_time();
        return if (t > 0) @intCast(t) else 0;
    }

    pub fn getUptimeMs() u64 {
        return getUptimeUs() / 1000;
    }

    pub fn mockSetUptimeMs(ms: u64) void {
        mock_uptime_us = @intCast(ms * 1000);
    }
};

test "system heap query and uptime in test environment" {
    try std.testing.expectEqual(@as(u32, 320000), System.getFreeHeap());
    try std.testing.expectEqual(@as(u32, 300000), System.getMinimumFreeHeap());
    try std.testing.expectEqual(@as(u64, 1000), System.getUptimeMs());

    System.restart();
    try std.testing.expect(mock_restart_called);
}

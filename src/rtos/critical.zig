//! FreeRTOS Critical Section Management for Zig
//!
//! Provides architecture-safe interrupt disabling and critical section nesting
//! across ESP-IDF (SMP spinlock) and bare-metal targets.

const std = @import("std");
const builtin = @import("builtin");

const is_arm = (builtin.cpu.arch == .thumb);
const is_riscv = (builtin.cpu.arch == .riscv32);
const is_xtensa = (builtin.cpu.arch == .xtensa);
const is_embedded = !builtin.is_test and (is_arm or is_riscv or is_xtensa);

extern fn vPortEnterCritical() callconv(.c) void;
extern fn vPortExitCritical() callconv(.c) void;

pub fn enterCritical() void {
    if (is_embedded) {
        vPortEnterCritical();
    }
}

pub fn exitCritical() void {
    if (is_embedded) {
        vPortExitCritical();
    }
}

pub const CriticalGuard = struct {
    pub fn enter() CriticalGuard {
        enterCritical();
        return .{};
    }

    pub fn exit(_: CriticalGuard) void {
        exitCritical();
    }
};

test "critical guard compilation and mock behavior" {
    const guard = CriticalGuard.enter();
    defer guard.exit();
}

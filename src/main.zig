//! Basic FreeRTOS + Zig Project Template on ESP-IDF
//!
//! A clean, modular starter project demonstrating:
//! - FreeRTOS tasks (`rtos.Task.spawn`)
//! - FreeRTOS typed message queues (`rtos.Queue(T)`)
//! - FreeRTOS mutexes with RAII lock guards (`rtos.Mutex.acquire` + `defer lock.release()`)
//! - Non-blocking console UART I/O & software bootloader trigger

const std = @import("std");
pub const hal = @import("hal");
pub const rtos = @import("rtos");

pub const PROJECT_NAME = "zig-esp-idf";
pub const PROJECT_VERSION = "0.1.0";

// Freestanding panic handler
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    hal.uart.ConsoleUart.print("\n[ZIG PANIC] %.*s\n", .{@as(c_int, @intCast(msg.len)), msg.ptr});
    while (true) {
        asm volatile ("nop");
    }
}

// Global typed queue and shared mutex
var counter_queue: rtos.Queue(u32) = undefined;
var print_mutex: rtos.Mutex = undefined;

/// Background Worker Task
fn workerTask(_: ?*anyopaque) void {
    hal.uart.ConsoleUart.print("[TASK] Worker task started successfully.\n", .{});

    while (true) {
        // Receive item from queue with 1-second timeout
        if (counter_queue.receive(1000)) |count| {
            // Acquire mutex with RAII lock guard
            if (print_mutex.acquire(100)) |lock| {
                defer lock.release();
                const free_heap = hal.system.System.getFreeHeap();
                const watermark = rtos.Task.getStackHighWaterMark(null);
                hal.uart.ConsoleUart.print(
                    "[TASK] Processed item #%u | Free Heap: %u bytes | Stack Watermark: %u bytes\n",
                    .{ count, free_heap, watermark },
                );
            } else |_| {
                hal.uart.ConsoleUart.print("[TASK] Failed to acquire print mutex within timeout\n", .{});
            }
        }
    }
}

/// ESP-IDF Application Entry Point
pub export fn app_main() void {
    // 1. Greeting banner
    hal.uart.ConsoleUart.print("\n", .{});
    hal.uart.ConsoleUart.print("=====================================================\n", .{});
    hal.uart.ConsoleUart.print("  %s v%s (Zig 0.17 + FreeRTOS)\n", .{ PROJECT_NAME, PROJECT_VERSION });
    hal.uart.ConsoleUart.print("  Free Heap: %u bytes (Min: %u bytes)\n", .{
        hal.system.System.getFreeHeap(),
        hal.system.System.getMinimumFreeHeap(),
    });
    hal.uart.ConsoleUart.print("=====================================================\n\n", .{});

    // 2. Initialize FreeRTOS synchronization primitives
    counter_queue = rtos.Queue(u32).init(8) catch {
        hal.uart.ConsoleUart.print("[ERROR] Failed to allocate queue\n", .{});
        return;
    };

    print_mutex = rtos.Mutex.create() catch {
        hal.uart.ConsoleUart.print("[ERROR] Failed to create mutex\n", .{});
        return;
    };

    // 3. Spawn background worker task
    _ = rtos.Task.spawn(
        "worker",
        3072, // Stack size in bytes (ESP-IDF)
        5,    // Priority
        workerTask,
        null,
    ) catch {
        hal.uart.ConsoleUart.print("[ERROR] Failed to spawn worker task\n", .{});
        return;
    };

    hal.uart.ConsoleUart.print("[MAIN] Entering event loop. Press 'b' to reboot to bootloader.\n", .{});

    var counter: u32 = 0;
    while (true) {
        // Poll console UART for incoming characters
        while (hal.uart.ConsoleUart.readByte()) |b| {
            if (hal.uart.checkUpdateCommand(b) == .reboot_bootloader) {
                hal.uart.ConsoleUart.print("\n[MAIN] Rebooting to ROM download bootloader...\n", .{});
                rtos.Task.delayMs(50);
                hal.uart.ConsoleUart.rebootToBootloader();
            } else if (b == 'p' or b == 'P') {
                hal.uart.ConsoleUart.print("[MAIN] Free heap: %u B, Uptime: %u ms\n", .{
                    hal.system.System.getFreeHeap(),
                    @as(u32, @truncate(hal.system.System.getUptimeMs())),
                });
            }
        }

        counter +%= 1;
        counter_queue.send(counter, 10) catch {};

        // Periodic delay (1000 ms)
        rtos.Task.delayMs(1000);
    }
}

// ============================================================================
// Host Unit Tests
// ============================================================================

test "project metadata" {
    try std.testing.expectEqualStrings("zig-esp-idf", PROJECT_NAME);
    try std.testing.expectEqualStrings("0.1.0", PROJECT_VERSION);
}

test "full test suite inclusion: hal + rtos" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(hal);
    std.testing.refAllDecls(rtos);
}

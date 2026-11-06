//! FreeRTOS Task Management Abstraction for Zig
//!
//! Provides unified task management for:
//! 1. Dynamic Task Spawning (`Task.spawn` on ESP-IDF / FreeRTOS heap)
//! 2. Static Task Creation (`Task.createStatic` for zero-heap architectures)
//! 3. Standard delays, yield, context switches, and direct-to-task notifications
//! 4. Comprehensive mock support for host testing on macOS/Linux

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

pub const TaskHandle = types.TaskHandle_t;
pub const TaskFunction = *const fn (ctx: ?*anyopaque) callconv(.c) void;
pub const tskNO_AFFINITY: types.BaseType_t = 0x7FFFFFFF;

const is_arm = (builtin.cpu.arch == .thumb);
const is_riscv = (builtin.cpu.arch == .riscv32);
const is_xtensa = (builtin.cpu.arch == .xtensa);
const is_embedded = !builtin.is_test and (is_arm or is_riscv or is_xtensa);

// ============================================================================
// FreeRTOS C Task Declarations
// ============================================================================

extern fn xTaskCreatePinnedToCore(
    pxTaskCode: TaskFunction,
    pcName: [*:0]const u8,
    usStackDepth: u32,
    pvParameters: ?*anyopaque,
    uxPriority: types.UBaseType_t,
    pxCreatedTask: ?*TaskHandle,
    xCoreID: types.BaseType_t,
) callconv(.c) types.BaseType_t;

extern fn xTaskCreateStatic(
    pxTaskCode: types.TaskFunction_t,
    pcName: [*:0]const u8,
    ulStackDepth: u32,
    pvParameters: ?*anyopaque,
    uxPriority: types.UBaseType_t,
    puxStackBuffer: [*]types.StackType_t,
    pxTaskBuffer: *types.StaticTask_t,
) callconv(.c) TaskHandle;

extern fn vTaskDelay(xTicksToDelay: types.TickType_t) callconv(.c) void;
extern fn vTaskDelayUntil(pxPreviousWakeTime: *types.TickType_t, xTimeIncrement: types.TickType_t) callconv(.c) void;
extern fn taskYIELD() callconv(.c) void;
extern fn xTaskGetTickCount() callconv(.c) types.TickType_t;
extern fn uxTaskGetStackHighWaterMark(xTask: TaskHandle) callconv(.c) types.UBaseType_t;
extern fn vTaskSuspend(xTaskToSuspend: TaskHandle) callconv(.c) void;
extern fn vTaskResume(xTaskToResume: TaskHandle) callconv(.c) void;
extern fn vTaskDelete(xTask: TaskHandle) callconv(.c) void;
extern fn vTaskStartScheduler() callconv(.c) void;
extern fn xTaskGetSchedulerState() callconv(.c) types.BaseType_t;

extern fn xTaskGenericNotify(
    xTaskToNotify: TaskHandle,
    uxIndexToNotify: types.UBaseType_t,
    ulValue: u32,
    eAction: types.eNotifyAction,
    pulPreviousNotificationValue: ?*u32,
) callconv(.c) types.BaseType_t;

extern fn xTaskGenericNotifyWait(
    uxIndexToWaitOn: types.UBaseType_t,
    ulBitsToClearOnEntry: u32,
    ulBitsToClearOnExit: u32,
    pulNotificationValue: ?*u32,
    xTicksToWait: types.TickType_t,
) callconv(.c) types.BaseType_t;

extern fn xTaskGenericNotifyFromISR(
    xTaskToNotify: TaskHandle,
    uxIndexToNotify: types.UBaseType_t,
    ulValue: u32,
    eAction: types.eNotifyAction,
    pulPreviousNotificationValue: ?*u32,
    pxHigherPriorityTaskWoken: *types.BaseType_t,
) callconv(.c) types.BaseType_t;

// ============================================================================
// Host Test Mocks
// ============================================================================

var mock_tick_count: types.TickType_t = 0;
var mock_stack_watermark: types.UBaseType_t = 2048;

fn mock_xTaskCreatePinnedToCore(
    _: TaskFunction,
    _: [*:0]const u8,
    _: u32,
    _: ?*anyopaque,
    _: types.UBaseType_t,
    pxCreatedTask: ?*TaskHandle,
    _: types.BaseType_t,
) callconv(.c) types.BaseType_t {
    if (pxCreatedTask) |p| p.* = @ptrFromInt(0x1234);
    return types.pdPASS;
}

fn mock_xTaskCreateStatic(
    _: types.TaskFunction_t,
    _: [*:0]const u8,
    _: u32,
    _: ?*anyopaque,
    _: types.UBaseType_t,
    _: [*]types.StackType_t,
    _: *types.StaticTask_t,
) callconv(.c) TaskHandle {
    return @ptrFromInt(0x2345);
}

fn mock_vTaskDelay(ticks: types.TickType_t) callconv(.c) void {
    mock_tick_count +%= ticks;
}

fn mock_vTaskDelayUntil(prev: *types.TickType_t, inc: types.TickType_t) callconv(.c) void {
    prev.* +%= inc;
    mock_tick_count = prev.*;
}

fn mock_taskYIELD() callconv(.c) void {}

fn mock_xTaskGetTickCount() callconv(.c) types.TickType_t {
    return mock_tick_count;
}

fn mock_uxTaskGetStackHighWaterMark(_: TaskHandle) callconv(.c) types.UBaseType_t {
    return mock_stack_watermark;
}

fn mock_vTaskDelete(_: TaskHandle) callconv(.c) void {}
fn mock_vTaskSuspend(_: TaskHandle) callconv(.c) void {}
fn mock_vTaskResume(_: TaskHandle) callconv(.c) void {}
fn mock_vTaskStartScheduler() callconv(.c) void {}
fn mock_xTaskGetSchedulerState() callconv(.c) types.BaseType_t {
    return types.taskSCHEDULER_RUNNING;
}

comptime {
    if (builtin.is_test) {
        @export(&mock_xTaskCreatePinnedToCore, .{ .name = "xTaskCreatePinnedToCore" });
        @export(&mock_xTaskCreateStatic, .{ .name = "xTaskCreateStatic" });
        @export(&mock_vTaskDelay, .{ .name = "vTaskDelay" });
        @export(&mock_vTaskDelayUntil, .{ .name = "vTaskDelayUntil" });
        @export(&mock_taskYIELD, .{ .name = "taskYIELD" });
        @export(&mock_xTaskGetTickCount, .{ .name = "xTaskGetTickCount" });
        @export(&mock_uxTaskGetStackHighWaterMark, .{ .name = "uxTaskGetStackHighWaterMark" });
        @export(&mock_vTaskDelete, .{ .name = "vTaskDelete" });
        @export(&mock_vTaskSuspend, .{ .name = "vTaskSuspend" });
        @export(&mock_vTaskResume, .{ .name = "vTaskResume" });
        @export(&mock_vTaskStartScheduler, .{ .name = "vTaskStartScheduler" });
        @export(&mock_xTaskGetSchedulerState, .{ .name = "xTaskGetSchedulerState" });
    }
}

// ============================================================================
// Task Interface
// ============================================================================

pub const Task = struct {
    handle: TaskHandle,

    /// Dynamic Task Spawning (ESP-IDF / systems with FreeRTOS heap allocator)
    /// NOTE: In ESP-IDF FreeRTOS, stack_bytes is specified in BYTES.
    pub fn spawn(
        name: [*:0]const u8,
        stack_bytes: u32,
        priority: u32,
        func: anytype,
        param: ?*anyopaque,
    ) types.RtosError!Task {
        const Trampoline = struct {
            fn entry(ctx: ?*anyopaque) callconv(.c) void {
                func(ctx);
            }
        };
        const c_func: TaskFunction = &Trampoline.entry;

        var created: TaskHandle = null;
        const res = if (builtin.is_test)
            mock_xTaskCreatePinnedToCore(c_func, name, stack_bytes, param, priority, &created, tskNO_AFFINITY)
        else
            xTaskCreatePinnedToCore(c_func, name, stack_bytes, param, priority, &created, tskNO_AFFINITY);

        if (res != types.pdPASS or created == null) {
            return types.RtosError.TaskCreationFailed;
        }
        return Task{ .handle = created };
    }

    /// Static Task Creation (zero-heap targets)
    pub fn createStatic(
        comptime stack_words: u32,
        name: [*:0]const u8,
        priority: types.UBaseType_t,
        func: types.TaskFunction_t,
        param: ?*anyopaque,
        stack_buf: *[stack_words]types.StackType_t,
        tcb_buf: *types.StaticTask_t,
    ) Task {
        const handle = if (builtin.is_test)
            mock_xTaskCreateStatic(func, name, stack_words, param, priority, stack_buf, tcb_buf)
        else
            xTaskCreateStatic(func, name, stack_words, param, priority, stack_buf, tcb_buf);
        return Task{ .handle = handle };
    }

    pub fn suspendTask(self: Task) void {
        if (builtin.is_test) {
            mock_vTaskSuspend(self.handle);
        } else {
            vTaskSuspend(self.handle);
        }
    }

    pub fn resumeTask(self: Task) void {
        if (builtin.is_test) {
            mock_vTaskResume(self.handle);
        } else {
            vTaskResume(self.handle);
        }
    }

    pub fn delete(self: Task) void {
        if (builtin.is_test) {
            mock_vTaskDelete(self.handle);
        } else {
            vTaskDelete(self.handle);
        }
    }

    pub fn getStackHighWaterMark(self: ?Task) u32 {
        const h = if (self) |t| t.handle else null;
        return if (builtin.is_test)
            @intCast(mock_uxTaskGetStackHighWaterMark(h))
        else
            @intCast(uxTaskGetStackHighWaterMark(h));
    }

    /// Delay current task for given FreeRTOS ticks
    pub fn delay(ticks: types.TickType_t) void {
        if (builtin.is_test) {
            mock_vTaskDelay(ticks);
        } else {
            vTaskDelay(ticks);
        }
    }

    /// Delay current task for given milliseconds
    pub fn delayMs(ms: u32) void {
        Task.delay(types.msToTicks(ms));
    }

    /// Delay until specific wake time (fixed-frequency periodic tasks)
    pub fn delayUntil(previous_wake_time: *types.TickType_t, increment_ticks: types.TickType_t) void {
        if (builtin.is_test) {
            mock_vTaskDelayUntil(previous_wake_time, increment_ticks);
        } else {
            vTaskDelayUntil(previous_wake_time, increment_ticks);
        }
    }

    /// Yield processor to another task of equal priority
    pub fn yield() void {
        if (builtin.is_test) {
            mock_taskYIELD();
        } else {
            taskYIELD();
        }
    }

    /// Get current tick count
    pub fn getTickCount() types.TickType_t {
        return if (builtin.is_test)
            mock_xTaskGetTickCount()
        else
            xTaskGetTickCount();
    }
};

// ============================================================================
// FreeRTOS Execution Control
// ============================================================================

pub const delay = Task.delay;
pub const delayMs = Task.delayMs;
pub const delayUntil = Task.delayUntil;
pub const yield = Task.yield;
pub const getTickCount = Task.getTickCount;

/// Request context switch from ISR
pub fn yieldFromISR(higher_priority_task_woken: types.BaseType_t) void {
    if (higher_priority_task_woken != 0) {
        if (is_arm) {
            const ICSR: *volatile u32 = @ptrFromInt(0xE000ED04);
            ICSR.* = (1 << 28); // PENDSVSET
        } else if (!builtin.is_test) {
            taskYIELD();
        }
    }
}

/// Get scheduler state (RUNNING, NOT_STARTED, SUSPENDED)
pub fn getSchedulerState() types.BaseType_t {
    return if (builtin.is_test)
        mock_xTaskGetSchedulerState()
    else
        xTaskGetSchedulerState();
}

/// Start FreeRTOS multitasking scheduler
pub fn startScheduler() noreturn {
    if (builtin.is_test) {
        mock_vTaskStartScheduler();
        while (true) {}
    } else {
        vTaskStartScheduler();
        while (true) {}
    }
}

// ============================================================================
// Direct-to-Task Notifications
// ============================================================================

pub inline fn notifyGive(target_task: TaskHandle) bool {
    if (builtin.is_test) return true;
    return xTaskGenericNotify(target_task, 0, 0, .eIncrement, null) == types.pdPASS;
}

pub inline fn notifyWait(
    clear_on_entry: u32,
    clear_on_exit: u32,
    out_val: ?*u32,
    wait_ticks: types.TickType_t,
) bool {
    if (builtin.is_test) return true;
    return xTaskGenericNotifyWait(0, clear_on_entry, clear_on_exit, out_val, wait_ticks) == types.pdTRUE;
}

pub inline fn notifyFromISR(
    target_task: TaskHandle,
    index: types.UBaseType_t,
    value: u32,
    action: types.eNotifyAction,
    prev_val: ?*u32,
    higher_priority_task_woken: *types.BaseType_t,
) bool {
    if (builtin.is_test) {
        higher_priority_task_woken.* = types.pdTRUE;
        return true;
    }
    return xTaskGenericNotifyFromISR(target_task, index, value, action, prev_val, higher_priority_task_woken) == types.pdPASS;
}

// ============================================================================
// Unit Tests
// ============================================================================

fn testTaskCode(_: ?*anyopaque) callconv(.c) void {}

test "task dynamic spawn and stack watermark" {
    const t = try Task.spawn("test_task", 2048, 5, testTaskCode, null);
    try std.testing.expect(t.handle != null);
    try std.testing.expectEqual(@as(u32, 2048), Task.getStackHighWaterMark(t));
}

test "task static creation" {
    var stack: [128]types.StackType_t = undefined;
    var tcb: types.StaticTask_t = .{};
    const t = Task.createStatic(128, "static_task", 3, testTaskCode, null, &stack, &tcb);
    try std.testing.expect(t.handle != null);
}

test "task delay and tick progression" {
    const before = getTickCount();
    delay(50);
    const after = getTickCount();
    try std.testing.expectEqual(before + 50, after);
}

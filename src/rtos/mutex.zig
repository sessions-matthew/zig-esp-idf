//! FreeRTOS Mutex and Semaphore Abstraction for Zig
//!
//! Provides RAII lock guards (via `defer lock.release()`), static mutexes,
//! and binary semaphores for ESP-IDF and bare-metal targets.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const queue = @import("queue.zig");

pub const SemaphoreHandle = types.SemaphoreHandle_t;

// ============================================================================
// FreeRTOS C Semaphore Declarations
// ============================================================================

extern fn xQueueCreateMutex(ucQueueType: u8) callconv(.c) SemaphoreHandle;

extern fn xQueueCreateMutexStatic(
    ucQueueType: u8,
    pxStaticQueue: *types.StaticQueue_t,
) callconv(.c) SemaphoreHandle;

extern fn xQueueSemaphoreTake(
    xQueue: SemaphoreHandle,
    xTicksToWait: types.TickType_t,
) callconv(.c) types.BaseType_t;

extern fn xQueueGenericSend(
    xQueue: SemaphoreHandle,
    pvItemToQueue: ?*const anyopaque,
    xTicksToWait: types.TickType_t,
    xCopyPosition: types.BaseType_t,
) callconv(.c) types.BaseType_t;

extern fn vQueueDelete(xQueue: SemaphoreHandle) callconv(.c) void;

// Host test mocks
pub var mock_mutex_locked: bool = false;

fn mock_xQueueCreateMutex(_: u8) callconv(.c) SemaphoreHandle {
    mock_mutex_locked = false;
    return @ptrFromInt(0x9ABC);
}

fn mock_xQueueCreateMutexStatic(_: u8, _: *types.StaticQueue_t) callconv(.c) SemaphoreHandle {
    mock_mutex_locked = false;
    return @ptrFromInt(0x9DEF);
}

fn mock_xQueueSemaphoreTake(_: SemaphoreHandle, _: types.TickType_t) callconv(.c) types.BaseType_t {
    if (!mock_mutex_locked) {
        mock_mutex_locked = true;
        return types.pdPASS;
    }
    return types.pdFAIL;
}

fn mock_xQueueGenericSend(_: SemaphoreHandle, _: ?*const anyopaque, _: types.TickType_t, _: types.BaseType_t) callconv(.c) types.BaseType_t {
    mock_mutex_locked = false;
    return types.pdPASS;
}

comptime {
    if (builtin.is_test) {
        @export(&mock_xQueueCreateMutex, .{ .name = "xQueueCreateMutex" });
        @export(&mock_xQueueCreateMutexStatic, .{ .name = "xQueueCreateMutexStatic" });
        @export(&mock_xQueueSemaphoreTake, .{ .name = "xQueueSemaphoreTake" });
    }
}

// ============================================================================
// Mutex & RAII Lock Guard
// ============================================================================

pub const Mutex = struct {
    handle: SemaphoreHandle = null,
    storage: types.StaticQueue_t = .{},

    pub const Lock = struct {
        handle: SemaphoreHandle,

        /// Release the mutex lock
        pub fn release(self: Lock) void {
            if (builtin.is_test) {
                _ = mock_xQueueGenericSend(self.handle, null, 0, 0);
            } else {
                _ = xQueueGenericSend(self.handle, null, 0, 0);
            }
        }
    };

    /// Create and initialize a dynamic FreeRTOS mutex (ESP-IDF heap)
    pub fn create() types.RtosError!Mutex {
        const h = if (builtin.is_test)
            mock_xQueueCreateMutex(types.queueQUEUE_TYPE_MUTEX)
        else
            xQueueCreateMutex(types.queueQUEUE_TYPE_MUTEX);

        if (h == null) return types.RtosError.OutOfMemory;
        return .{ .handle = h };
    }

    /// Initialize a static mutex using embedded StaticQueue_t (zero heap)
    pub fn init(self: *Mutex) void {
        self.initStatic();
    }

    /// Initialize a static mutex using embedded StaticQueue_t (zero heap)
    pub fn initStatic(self: *Mutex) void {
        self.handle = if (builtin.is_test)
            mock_xQueueCreateMutexStatic(types.queueQUEUE_TYPE_MUTEX, &self.storage)
        else
            xQueueCreateMutexStatic(types.queueQUEUE_TYPE_MUTEX, &self.storage);
    }

    /// Low-level take (blocking)
    pub fn take(self: *Mutex, wait_ticks: types.TickType_t) bool {
        if (self.handle == null) self.initStatic();
        const res = if (builtin.is_test)
            mock_xQueueSemaphoreTake(self.handle, wait_ticks)
        else
            xQueueSemaphoreTake(self.handle, wait_ticks);
        return res == types.pdPASS;
    }

    /// Low-level give
    pub fn give(self: *Mutex) bool {
        if (self.handle == null) return false;
        const res = if (builtin.is_test)
            mock_xQueueGenericSend(self.handle, null, 0, types.queueSEND_TO_BACK)
        else
            xQueueGenericSend(self.handle, null, 0, types.queueSEND_TO_BACK);
        return res == types.pdPASS;
    }

    /// Acquire the mutex with a millisecond timeout. Returns an RAII Lock guard.
    pub fn acquire(self: *Mutex, timeout_ms: u32) types.RtosError!Lock {
        const ticks = types.msToTicks(timeout_ms);
        if (!self.take(ticks)) {
            return types.RtosError.MutexAcquisitionFailed;
        }
        return Lock{ .handle = self.handle };
    }

    /// Try to acquire the mutex immediately without blocking
    pub fn tryAcquire(self: *Mutex) types.RtosError!Lock {
        return self.acquire(0);
    }

    /// Destroy dynamic mutex
    pub fn deinit(self: *Mutex) void {
        if (self.handle) |h| {
            if (!builtin.is_test) {
                vQueueDelete(h);
            }
            self.handle = null;
        }
    }
};

// ============================================================================
// Static Binary Semaphore
// ============================================================================

pub const Semaphore = struct {
    q: queue.StaticQueue(u8, 1) = .{},

    pub fn init(self: *Semaphore) void {
        self.q.init();
    }

    pub fn take(self: *Semaphore, wait_ticks: types.TickType_t) bool {
        var dummy: u8 = 0;
        return self.q.receive(&dummy, wait_ticks);
    }

    pub fn give(self: *Semaphore) bool {
        const dummy: u8 = 0;
        return self.q.send(&dummy, 0);
    }

    pub fn giveFromISR(self: *Semaphore, higher_priority_task_woken: *types.BaseType_t) bool {
        const dummy: u8 = 0;
        return self.q.sendFromISR(&dummy, higher_priority_task_woken);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "mutex acquire and release with defer RAII guard" {
    var m = try Mutex.create();
    defer m.deinit();

    {
        const lock = try m.acquire(100);
        defer lock.release();
        try std.testing.expect(mock_mutex_locked);
    }
    try std.testing.expect(!mock_mutex_locked);
}

test "static mutex acquire and release" {
    var m: Mutex = .{};
    m.initStatic();

    try std.testing.expect(m.take(10));
    try std.testing.expect(mock_mutex_locked);
    try std.testing.expect(m.give());
    try std.testing.expect(!mock_mutex_locked);
}

//! FreeRTOS Generic Queue Abstraction for Zig
//!
//! Provides two compile-time type-checked queue models:
//! 1. `Queue(T)`: Dynamic queue with runtime capacity (allocated from FreeRTOS heap)
//! 2. `StaticQueue(T, capacity)`: Compile-time sized queue with zero heap allocation

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

pub const QueueHandle = types.QueueHandle_t;

// ============================================================================
// FreeRTOS C Queue Declarations
// ============================================================================

extern fn xQueueGenericCreate(
    uxQueueLength: types.UBaseType_t,
    uxItemSize: types.UBaseType_t,
    ucQueueType: u8,
) callconv(.c) QueueHandle;

extern fn xQueueGenericCreateStatic(
    uxQueueLength: types.UBaseType_t,
    uxItemSize: types.UBaseType_t,
    pucQueueStorage: [*]u8,
    pxStaticQueue: *types.StaticQueue_t,
    ucQueueType: u8,
) callconv(.c) QueueHandle;

extern fn xQueueGenericSend(
    xQueue: QueueHandle,
    pvItemToQueue: ?*const anyopaque,
    xTicksToWait: types.TickType_t,
    xCopyPosition: types.BaseType_t,
) callconv(.c) types.BaseType_t;

extern fn xQueueReceive(
    xQueue: QueueHandle,
    pvBuffer: ?*anyopaque,
    xTicksToWait: types.TickType_t,
) callconv(.c) types.BaseType_t;

extern fn xQueueGenericSendFromISR(
    xQueue: QueueHandle,
    pvItemToQueue: ?*const anyopaque,
    pxHigherPriorityTaskWoken: *types.BaseType_t,
    xCopyPosition: types.BaseType_t,
) callconv(.c) types.BaseType_t;

extern fn xQueueReceiveFromISR(
    xQueue: QueueHandle,
    pvBuffer: ?*anyopaque,
    pxHigherPriorityTaskWoken: *types.BaseType_t,
) callconv(.c) types.BaseType_t;

extern fn uxQueueMessagesWaiting(xQueue: QueueHandle) callconv(.c) types.UBaseType_t;
extern fn uxQueueSpacesAvailable(xQueue: QueueHandle) callconv(.c) types.UBaseType_t;
extern fn vQueueDelete(xQueue: QueueHandle) callconv(.c) void;
extern fn xQueueReset(xQueue: QueueHandle) callconv(.c) types.BaseType_t;

// ============================================================================
// Host Test Mock Queue Storage
// ============================================================================

var mock_queue_storage: [1024]u8 = undefined;
var mock_queue_head: usize = 0;
var mock_queue_tail: usize = 0;
var mock_queue_item_size: usize = 0;
var mock_queue_capacity: usize = 0;

fn mock_xQueueGenericCreate(
    uxQueueLength: types.UBaseType_t,
    uxItemSize: types.UBaseType_t,
    _: u8,
) callconv(.c) QueueHandle {
    mock_queue_head = 0;
    mock_queue_tail = 0;
    mock_queue_capacity = uxQueueLength;
    mock_queue_item_size = uxItemSize;
    return @ptrFromInt(0x5678);
}

fn mock_xQueueGenericCreateStatic(
    uxQueueLength: types.UBaseType_t,
    uxItemSize: types.UBaseType_t,
    _: [*]u8,
    _: *types.StaticQueue_t,
    _: u8,
) callconv(.c) QueueHandle {
    mock_queue_head = 0;
    mock_queue_tail = 0;
    mock_queue_capacity = uxQueueLength;
    mock_queue_item_size = uxItemSize;
    return @ptrFromInt(0x6789);
}

fn mock_xQueueGenericSend(
    _: QueueHandle,
    pvItemToQueue: ?*const anyopaque,
    _: types.TickType_t,
    _: types.BaseType_t,
) callconv(.c) types.BaseType_t {
    if (pvItemToQueue) |src| {
        const waiting = (mock_queue_head + mock_queue_capacity - mock_queue_tail) % mock_queue_capacity;
        if (waiting >= mock_queue_capacity - 1) return types.pdFAIL;

        const src_bytes: [*]const u8 = @ptrCast(src);
        const dest = mock_queue_head * mock_queue_item_size;
        @memcpy(mock_queue_storage[dest .. dest + mock_queue_item_size], src_bytes[0..mock_queue_item_size]);
        mock_queue_head = (mock_queue_head + 1) % mock_queue_capacity;
        return types.pdPASS;
    }
    return types.pdPASS;
}

fn mock_xQueueReceive(
    _: QueueHandle,
    pvBuffer: ?*anyopaque,
    _: types.TickType_t,
) callconv(.c) types.BaseType_t {
    if (mock_queue_head == mock_queue_tail) return types.pdFAIL;

    if (pvBuffer) |dst| {
        const dst_bytes: [*]u8 = @ptrCast(dst);
        const src = mock_queue_tail * mock_queue_item_size;
        @memcpy(dst_bytes[0..mock_queue_item_size], mock_queue_storage[src .. src + mock_queue_item_size]);
        mock_queue_tail = (mock_queue_tail + 1) % mock_queue_capacity;
    }
    return types.pdPASS;
}

fn mock_uxQueueMessagesWaiting(_: QueueHandle) callconv(.c) types.UBaseType_t {
    return (mock_queue_head + mock_queue_capacity - mock_queue_tail) % mock_queue_capacity;
}

fn mock_uxQueueSpacesAvailable(_: QueueHandle) callconv(.c) types.UBaseType_t {
    const waiting = (mock_queue_head + mock_queue_capacity - mock_queue_tail) % mock_queue_capacity;
    return mock_queue_capacity - 1 - waiting;
}

fn mock_vQueueDelete(_: QueueHandle) callconv(.c) void {}

fn mock_xQueueReset(_: QueueHandle) callconv(.c) types.BaseType_t {
    mock_queue_head = 0;
    mock_queue_tail = 0;
    return types.pdPASS;
}

comptime {
    if (builtin.is_test) {
        @export(&mock_xQueueGenericCreate, .{ .name = "xQueueGenericCreate" });
        @export(&mock_xQueueGenericCreateStatic, .{ .name = "xQueueGenericCreateStatic" });
        @export(&mock_xQueueGenericSend, .{ .name = "xQueueGenericSend" });
        @export(&mock_xQueueReceive, .{ .name = "xQueueReceive" });
        @export(&mock_uxQueueMessagesWaiting, .{ .name = "uxQueueMessagesWaiting" });
        @export(&mock_uxQueueSpacesAvailable, .{ .name = "uxQueueSpacesAvailable" });
        @export(&mock_vQueueDelete, .{ .name = "vQueueDelete" });
        @export(&mock_xQueueReset, .{ .name = "xQueueReset" });
    }
}

// ============================================================================
// Model 1: Dynamic Heap-Allocated Queue (ESP-IDF)
// ============================================================================

pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const ItemType = T;

        handle: QueueHandle,

        pub fn init(capacity: usize) types.RtosError!Self {
            const h = if (builtin.is_test)
                mock_xQueueGenericCreate(@intCast(capacity + 1), @sizeOf(T), types.queueQUEUE_TYPE_BASE)
            else
                xQueueGenericCreate(@intCast(capacity), @sizeOf(T), types.queueQUEUE_TYPE_BASE);

            if (h == null) return types.RtosError.OutOfMemory;
            return Self{ .handle = h };
        }

        pub fn deinit(self: *Self) void {
            if (builtin.is_test) {
                mock_vQueueDelete(self.handle);
            } else {
                vQueueDelete(self.handle);
            }
        }

        pub fn send(self: *Self, item: T, timeout_ms: u32) types.RtosError!void {
            const ticks = types.msToTicks(timeout_ms);
            const res = if (builtin.is_test)
                mock_xQueueGenericSend(self.handle, &item, ticks, types.queueSEND_TO_BACK)
            else
                xQueueGenericSend(self.handle, &item, ticks, types.queueSEND_TO_BACK);

            if (res != types.pdPASS) return types.RtosError.QueueFull;
        }

        pub fn receive(self: *Self, timeout_ms: u32) ?T {
            const ticks = types.msToTicks(timeout_ms);
            var item: T = undefined;
            const res = if (builtin.is_test)
                mock_xQueueReceive(self.handle, &item, ticks)
            else
                xQueueReceive(self.handle, &item, ticks);

            if (res == types.pdPASS) return item;
            return null;
        }

        pub fn messagesWaiting(self: *const Self) usize {
            return if (builtin.is_test)
                mock_uxQueueMessagesWaiting(self.handle)
            else
                uxQueueMessagesWaiting(self.handle);
        }

        pub fn spacesAvailable(self: *const Self) usize {
            return if (builtin.is_test)
                mock_uxQueueSpacesAvailable(self.handle)
            else
                uxQueueSpacesAvailable(self.handle);
        }

        pub fn reset(self: *Self) void {
            if (builtin.is_test) {
                _ = mock_xQueueReset(self.handle);
            } else {
                _ = xQueueReset(self.handle);
            }
        }
    };
}

// ============================================================================
// Model 2: Static Zero-Allocation Queue
// ============================================================================

pub fn StaticQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        pub const ItemType = T;
        pub const Capacity = capacity;

        handle: QueueHandle = null,
        storage: [capacity * @sizeOf(T)]u8 = undefined,
        tcb: types.StaticQueue_t = .{},

        pub fn init(self: *Self) void {
            self.handle = if (builtin.is_test)
                mock_xQueueGenericCreateStatic(
                    @intCast(capacity + 1),
                    @sizeOf(T),
                    &self.storage,
                    &self.tcb,
                    types.queueQUEUE_TYPE_BASE,
                )
            else
                xQueueGenericCreateStatic(
                    @intCast(capacity),
                    @sizeOf(T),
                    &self.storage,
                    &self.tcb,
                    types.queueQUEUE_TYPE_BASE,
                );
        }

        pub fn send(self: *Self, item: *const T, wait_ticks: types.TickType_t) bool {
            if (self.handle == null) self.init();
            const res = if (builtin.is_test)
                mock_xQueueGenericSend(self.handle, item, wait_ticks, types.queueSEND_TO_BACK)
            else
                xQueueGenericSend(self.handle, item, wait_ticks, types.queueSEND_TO_BACK);
            return res == types.pdPASS;
        }

        pub fn sendValue(self: *Self, item: T, wait_ticks: types.TickType_t) bool {
            return self.send(&item, wait_ticks);
        }

        pub fn sendToFront(self: *Self, item: *const T, wait_ticks: types.TickType_t) bool {
            if (self.handle == null) self.init();
            const res = if (builtin.is_test)
                mock_xQueueGenericSend(self.handle, item, wait_ticks, types.queueSEND_TO_FRONT)
            else
                xQueueGenericSend(self.handle, item, wait_ticks, types.queueSEND_TO_FRONT);
            return res == types.pdPASS;
        }

        pub fn overwrite(self: *Self, item: *const T) bool {
            if (self.handle == null) self.init();
            const res = if (builtin.is_test)
                mock_xQueueGenericSend(self.handle, item, 0, types.queueOVERWRITE)
            else
                xQueueGenericSend(self.handle, item, 0, types.queueOVERWRITE);
            return res == types.pdPASS;
        }

        pub fn receive(self: *Self, out: *T, wait_ticks: types.TickType_t) bool {
            if (self.handle == null) self.init();
            const res = if (builtin.is_test)
                mock_xQueueReceive(self.handle, out, wait_ticks)
            else
                xQueueReceive(self.handle, out, wait_ticks);
            return res == types.pdPASS;
        }

        pub fn receiveValue(self: *Self, wait_ticks: types.TickType_t) ?T {
            var val: T = undefined;
            if (self.receive(&val, wait_ticks)) return val;
            return null;
        }

        pub fn sendFromISR(self: *Self, item: *const T, higher_priority_task_woken: *types.BaseType_t) bool {
            if (self.handle == null) self.init();
            const res = if (builtin.is_test)
                mock_xQueueGenericSend(self.handle, item, 0, types.queueSEND_TO_BACK)
            else
                xQueueGenericSendFromISR(self.handle, item, higher_priority_task_woken, types.queueSEND_TO_BACK);
            return res == types.pdPASS;
        }

        pub fn receiveFromISR(self: *Self, out: *T, higher_priority_task_woken: *types.BaseType_t) bool {
            if (self.handle == null) self.init();
            const res = if (builtin.is_test)
                mock_xQueueReceive(self.handle, out, 0)
            else
                xQueueReceiveFromISR(self.handle, out, higher_priority_task_woken);
            return res == types.pdPASS;
        }

        pub fn messagesWaiting(self: *Self) usize {
            if (self.handle == null) return 0;
            return if (builtin.is_test)
                @intCast(mock_uxQueueMessagesWaiting(self.handle))
            else
                @intCast(uxQueueMessagesWaiting(self.handle));
        }

        pub fn spacesAvailable(self: *Self) usize {
            if (self.handle == null) return capacity;
            return if (builtin.is_test)
                @intCast(mock_uxQueueSpacesAvailable(self.handle))
            else
                @intCast(uxQueueSpacesAvailable(self.handle));
        }

        pub fn reset(self: *Self) void {
            if (self.handle) |h| {
                if (builtin.is_test) {
                    _ = mock_xQueueReset(h);
                } else {
                    _ = xQueueReset(h);
                }
            }
        }
    };
}

// ============================================================================
// Unit Tests
// ============================================================================

test "dynamic queue send and receive" {
    var q = try Queue(u32).init(4);
    defer q.deinit();

    try q.send(100, 0);
    try q.send(200, 0);

    try std.testing.expectEqual(@as(?u32, 100), q.receive(0));
    try std.testing.expectEqual(@as(?u32, 200), q.receive(0));
    try std.testing.expectEqual(@as(?u32, null), q.receive(0));
}

test "static queue send and receive" {
    var q: StaticQueue(i32, 4) = .{};
    q.init();

    const val1: i32 = -42;
    const val2: i32 = 84;
    try std.testing.expect(q.send(&val1, 0));
    try std.testing.expect(q.send(&val2, 0));

    var out: i32 = 0;
    try std.testing.expect(q.receive(&out, 0));
    try std.testing.expectEqual(@as(i32, -42), out);
    try std.testing.expect(q.receive(&out, 0));
    try std.testing.expectEqual(@as(i32, 84), out);
    try std.testing.expect(!q.receive(&out, 0));
}

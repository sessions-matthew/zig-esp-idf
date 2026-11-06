//! ESP32 Hardware Abstraction Layer - GPIO
//!
//! Provides zero-overhead compile-time GPIO abstractions with direct MMIO register access
//! and ESP-IDF runtime fallback. Includes mock implementations for native host testing.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// ESP32 GPIO MMIO Register Definitions (ESP32-C6 / generic RV32 DR_REG_GPIO_BASE = 0x60091000)
// ============================================================================

pub const GPIO_BASE: usize = 0x60091000;

pub const GpioMmio = extern struct {
    bt_select: u32, // 0x000
    out: u32, // 0x004
    out_w1ts: u32, // 0x008 (Write-1-to-Set)
    out_w1tc: u32, // 0x00C (Write-1-to-Clear)
    enable: u32, // 0x010
    enable_w1ts: u32, // 0x014 (Output enable set)
    enable_w1tc: u32, // 0x018 (Output enable clear)
    strap: u32, // 0x01C
    in: u32, // 0x020 (Input level)
    status: u32, // 0x024
    status_w1ts: u32, // 0x028
    status_w1tc: u32, // 0x02C
};

pub inline fn getGpioMmio() *volatile GpioMmio {
    return @ptrFromInt(GPIO_BASE);
}

// ============================================================================
// Types and Enums
// ============================================================================

pub const Level = enum(u1) {
    low = 0,
    high = 1,

    pub inline fn toBool(self: Level) bool {
        return self == .high;
    }

    pub inline fn fromBool(b: bool) Level {
        return if (b) .high else .low;
    }

    pub inline fn invert(self: Level) Level {
        return if (self == .high) .low else .high;
    }
};

pub const Polarity = enum {
    active_high,
    active_low,
};

pub const Mode = enum(u32) {
    disable = 0,
    input = 1,
    output = 2,
    output_od = 3,
    input_output_od = 4,
    input_output = 5,
};

pub const Pull = enum {
    none,
    pull_up,
    pull_down,
    pull_up_down,
};

// ============================================================================
// ESP-IDF C Runtime Bindings (or Mock during Host Testing)
// ============================================================================

extern fn gpio_reset_pin(gpio_num: i32) i32;
extern fn gpio_set_direction(gpio_num: i32, mode: u32) i32;
extern fn gpio_set_level(gpio_num: i32, level: u32) i32;
extern fn gpio_get_level(gpio_num: i32) i32;
extern fn gpio_pullup_en(gpio_num: i32) i32;
extern fn gpio_pullup_dis(gpio_num: i32) i32;
extern fn gpio_pulldown_en(gpio_num: i32) i32;
extern fn gpio_pulldown_dis(gpio_num: i32) i32;
extern fn gpio_set_drive_capability(gpio_num: i32, strength: u32) i32;

// Host test mock state
var mock_gpio_levels: [32]u1 = @splat(0);
var mock_gpio_directions: [32]Mode = @splat(.disable);

fn mock_gpio_reset_pin(gpio_num: i32) callconv(.c) i32 {
    if (gpio_num >= 0 and gpio_num < 32) {
        mock_gpio_levels[@intCast(gpio_num)] = 0;
        mock_gpio_directions[@intCast(gpio_num)] = .disable;
    }
    return 0;
}
fn mock_gpio_set_direction(gpio_num: i32, mode: u32) callconv(.c) i32 {
    if (gpio_num >= 0 and gpio_num < 32) {
        mock_gpio_directions[@intCast(gpio_num)] = @enumFromInt(mode);
    }
    return 0;
}
fn mock_gpio_set_level(gpio_num: i32, level: u32) callconv(.c) i32 {
    if (gpio_num >= 0 and gpio_num < 32) {
        mock_gpio_levels[@intCast(gpio_num)] = @intCast(level & 1);
    }
    return 0;
}
fn mock_gpio_get_level(gpio_num: i32) callconv(.c) i32 {
    if (gpio_num >= 0 and gpio_num < 32) {
        return mock_gpio_levels[@intCast(gpio_num)];
    }
    return 0;
}
fn mock_gpio_pullup_en(_: i32) callconv(.c) i32 {
    return 0;
}
fn mock_gpio_pullup_dis(_: i32) callconv(.c) i32 {
    return 0;
}
fn mock_gpio_pulldown_en(_: i32) callconv(.c) i32 {
    return 0;
}
fn mock_gpio_pulldown_dis(_: i32) callconv(.c) i32 {
    return 0;
}
fn mock_gpio_set_drive_capability(_: i32, _: u32) callconv(.c) i32 {
    return 0;
}

comptime {
    if (builtin.is_test) {
        @export(&mock_gpio_reset_pin, .{ .name = "gpio_reset_pin" });
        @export(&mock_gpio_set_direction, .{ .name = "gpio_set_direction" });
        @export(&mock_gpio_set_level, .{ .name = "gpio_set_level" });
        @export(&mock_gpio_get_level, .{ .name = "gpio_get_level" });
        @export(&mock_gpio_pullup_en, .{ .name = "gpio_pullup_en" });
        @export(&mock_gpio_pullup_dis, .{ .name = "gpio_pullup_dis" });
        @export(&mock_gpio_pulldown_en, .{ .name = "gpio_pulldown_en" });
        @export(&mock_gpio_pulldown_dis, .{ .name = "gpio_pulldown_dis" });
        @export(&mock_gpio_set_drive_capability, .{ .name = "gpio_set_drive_capability" });
    }
}

// ============================================================================
// Hardware Output Pin
// ============================================================================

pub const OutputPin = struct {
    pin: u8,
    mask: u32,
    polarity: Polarity,

    pub const Config = struct {
        open_drain: bool = false,
        initial_state: bool = false, // false = inactive, true = active
    };

    pub fn init(pin_num: u8, polarity: Polarity) OutputPin {
        return .{
            .pin = pin_num,
            .mask = @as(u32, 1) << @as(u5, @intCast(pin_num & 0x1F)),
            .polarity = polarity,
        };
    }

    /// Configure the pin direction with ESP-IDF runtime
    pub fn configure(self: OutputPin, config: Config) void {
        _ = gpio_reset_pin(self.pin);
        const mode: Mode = if (config.open_drain) .output_od else .output;
        _ = gpio_set_direction(self.pin, @intFromEnum(mode));
        if (config.initial_state) {
            self.on();
        } else {
            self.off();
        }
    }

    /// Configure pad drive strength (0..3, where 3 is maximum drive capability)
    pub fn setDriveCapability(self: OutputPin, strength: u2) void {
        _ = gpio_set_drive_capability(self.pin, strength);
    }

    /// Enable or disable internal pull-up resistor on output pin
    pub fn setPullUp(self: OutputPin, enabled: bool) void {
        if (enabled) {
            _ = gpio_pullup_en(self.pin);
        } else {
            _ = gpio_pullup_dis(self.pin);
        }
    }

    /// Set electrical HIGH level directly
    pub inline fn setHigh(self: OutputPin) void {
        if (builtin.is_test) {
            _ = gpio_set_level(self.pin, 1);
        } else if (comptime builtin.cpu.arch == .riscv32) {
            getGpioMmio().out_w1ts = self.mask;
        } else {
            _ = gpio_set_level(self.pin, 1);
        }
    }

    /// Set electrical LOW level directly
    pub inline fn setLow(self: OutputPin) void {
        if (builtin.is_test) {
            _ = gpio_set_level(self.pin, 0);
        } else if (comptime builtin.cpu.arch == .riscv32) {
            getGpioMmio().out_w1tc = self.mask;
        } else {
            _ = gpio_set_level(self.pin, 0);
        }
    }

    /// Write raw level
    pub inline fn write(self: OutputPin, level: Level) void {
        switch (level) {
            .high => self.setHigh(),
            .low => self.setLow(),
        }
    }

    /// Assert active state (considers active_high vs active_low polarity)
    pub inline fn on(self: OutputPin) void {
        switch (self.polarity) {
            .active_high => self.setHigh(),
            .active_low => self.setLow(),
        }
    }

    /// Deassert inactive state (considers active_high vs active_low polarity)
    pub inline fn off(self: OutputPin) void {
        switch (self.polarity) {
            .active_high => self.setLow(),
            .active_low => self.setHigh(),
        }
    }

    /// Set logical state (true = on/active, false = off/inactive)
    pub inline fn set(self: OutputPin, active: bool) void {
        if (active) self.on() else self.off();
    }

    /// Toggle pin electrical level
    pub inline fn toggle(self: OutputPin) void {
        if (self.readLevel() == .high) {
            self.setLow();
        } else {
            self.setHigh();
        }
    }

    /// Read currently latched output level
    pub inline fn readLevel(self: OutputPin) Level {
        if (builtin.is_test) {
            return if (gpio_get_level(self.pin) != 0) .high else .low;
        } else if (comptime builtin.cpu.arch == .riscv32) {
            return if ((getGpioMmio().out & self.mask) != 0) .high else .low;
        } else {
            return if (gpio_get_level(self.pin) != 0) .high else .low;
        }
    }

    /// Read logical state (true if active)
    pub inline fn isActive(self: OutputPin) bool {
        const lvl = self.readLevel();
        return switch (self.polarity) {
            .active_high => lvl == .high,
            .active_low => lvl == .low,
        };
    }
};

// ============================================================================
// Hardware Input Pin
// ============================================================================

pub const InputPin = struct {
    pin: u8,
    mask: u32,
    polarity: Polarity,

    pub fn init(pin_num: u8, polarity: Polarity) InputPin {
        return .{
            .pin = pin_num,
            .mask = @as(u32, 1) << @as(u5, @intCast(pin_num & 0x1F)),
            .polarity = polarity,
        };
    }

    pub fn configure(self: InputPin, pull: Pull) void {
        _ = gpio_reset_pin(self.pin);
        _ = gpio_set_direction(self.pin, @intFromEnum(Mode.input));
        switch (pull) {
            .none => {
                _ = gpio_pullup_dis(self.pin);
                _ = gpio_pulldown_dis(self.pin);
            },
            .pull_up => {
                _ = gpio_pullup_en(self.pin);
                _ = gpio_pulldown_dis(self.pin);
            },
            .pull_down => {
                _ = gpio_pullup_dis(self.pin);
                _ = gpio_pulldown_en(self.pin);
            },
            .pull_up_down => {
                _ = gpio_pullup_en(self.pin);
                _ = gpio_pulldown_en(self.pin);
            },
        }
    }

    /// Read raw electrical level
    pub inline fn readLevel(self: InputPin) Level {
        if (builtin.is_test) {
            return if (gpio_get_level(self.pin) != 0) .high else .low;
        } else if (comptime builtin.cpu.arch == .riscv32) {
            return if ((getGpioMmio().in & self.mask) != 0) .high else .low;
        } else {
            return if (gpio_get_level(self.pin) != 0) .high else .low;
        }
    }

    /// Check if electrical level is HIGH
    pub inline fn isHigh(self: InputPin) bool {
        return self.readLevel() == .high;
    }

    /// Check if electrical level is LOW
    pub inline fn isLow(self: InputPin) bool {
        return self.readLevel() == .low;
    }

    /// Read logical state (true if active)
    pub inline fn isActive(self: InputPin) bool {
        const lvl = self.readLevel();
        return switch (self.polarity) {
            .active_high => lvl == .high,
            .active_low => lvl == .low,
        };
    }
};

// ============================================================================
// Mock Pin Implementations (For testing without any hardware)
// ============================================================================

pub const MockOutputPin = struct {
    level: Level = .low,
    polarity: Polarity = .active_high,
    toggle_count: u32 = 0,

    pub fn setHigh(self: *@This()) void {
        self.level = .high;
    }
    pub fn setLow(self: *@This()) void {
        self.level = .low;
    }
    pub fn setDriveCapability(_: *@This(), _: u2) void {}
    pub fn setPullUp(_: *@This(), _: bool) void {}
    pub fn on(self: *@This()) void {
        switch (self.polarity) {
            .active_high => self.setHigh(),
            .active_low => self.setLow(),
        }
    }
    pub fn off(self: *@This()) void {
        switch (self.polarity) {
            .active_high => self.setLow(),
            .active_low => self.setHigh(),
        }
    }
    pub fn set(self: *@This(), active: bool) void {
        if (active) self.on() else self.off();
    }
    pub fn toggle(self: *@This()) void {
        self.toggle_count += 1;
        self.level = self.level.invert();
    }
    pub fn readLevel(self: @This()) Level {
        return self.level;
    }
    pub fn isActive(self: @This()) bool {
        return switch (self.polarity) {
            .active_high => self.level == .high,
            .active_low => self.level == .low,
        };
    }
};

pub const MockInputPin = struct {
    level: Level = .low,
    polarity: Polarity = .active_high,

    pub fn setLevel(self: *@This(), lvl: Level) void {
        self.level = lvl;
    }
    pub fn readLevel(self: @This()) Level {
        return self.level;
    }
    pub fn isHigh(self: @This()) bool {
        return self.level == .high;
    }
    pub fn isLow(self: @This()) bool {
        return self.level == .low;
    }
    pub fn isActive(self: @This()) bool {
        return switch (self.polarity) {
            .active_high => self.level == .high,
            .active_low => self.level == .low,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "output pin active-high polarity" {
    var pin = OutputPin.init(5, .active_high);
    pin.configure(.{ .initial_state = false });

    try std.testing.expectEqual(Level.low, pin.readLevel());
    try std.testing.expect(!pin.isActive());

    pin.on();
    try std.testing.expectEqual(Level.high, pin.readLevel());
    try std.testing.expect(pin.isActive());

    pin.off();
    try std.testing.expectEqual(Level.low, pin.readLevel());
    try std.testing.expect(!pin.isActive());

    pin.toggle();
    try std.testing.expectEqual(Level.high, pin.readLevel());
}

test "output pin active-low polarity" {
    var pin = OutputPin.init(10, .active_low);
    pin.configure(.{ .open_drain = true, .initial_state = false });

    try std.testing.expectEqual(Level.high, pin.readLevel());
    try std.testing.expect(!pin.isActive());

    pin.on();
    try std.testing.expectEqual(Level.low, pin.readLevel());
    try std.testing.expect(pin.isActive());

    pin.off();
    try std.testing.expectEqual(Level.high, pin.readLevel());
}

test "mock pin testing interface" {
    var mock = MockOutputPin{ .polarity = .active_low };
    mock.off();
    try std.testing.expectEqual(Level.high, mock.level);
    try std.testing.expect(!mock.isActive());

    mock.on();
    try std.testing.expectEqual(Level.low, mock.level);
    try std.testing.expect(mock.isActive());

    mock.toggle();
    try std.testing.expectEqual(Level.high, mock.level);
    try std.testing.expectEqual(@as(u32, 1), mock.toggle_count);
}

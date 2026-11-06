//! ESP32 Hardware Abstraction Layer - UART
//!
//! Provides non-blocking console UART communication, command parsing helpers,
//! software download bootloader triggering, and generic multi-port UART driver (UART0, UART1, etc.)
//! backed by ESP-IDF driver/uart.h with comprehensive host test mocks.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Low-Power AON Registers (ESP32-C6 Reset Control)
// ============================================================================

pub const LP_AON_BASE: usize = 0x600B1000;
pub const LP_AON_SYS_CFG_REG: usize = LP_AON_BASE + 0x34;

pub const LP_AON_FORCE_DOWNLOAD_BOOT: u32 = 1 << 30;
pub const LP_AON_HPSYS_SW_RESET: u32 = 1 << 31;

pub const LpAonMmio = extern struct {
    _reserved: [13]u32, // 0x00 .. 0x30
    sys_cfg: u32, // 0x34 (LP_AON_SYS_CFG_REG)
};

pub inline fn getLpAonMmio() *volatile LpAonMmio {
    return @ptrFromInt(LP_AON_BASE);
}

// ============================================================================
// ESP-IDF ROM UART Extern Bindings
// ============================================================================

extern fn esp_rom_uart_rx_one_char(c: *u8) i32;
extern fn esp_rom_uart_tx_one_char(c: u8) void;
extern fn esp_rom_printf(fmt: [*:0]const u8, ...) void;

// ============================================================================
// ESP-IDF Driver UART Types & Extern Bindings
// ============================================================================

pub const PortNumber = enum(c_int) {
    uart0 = 0,
    uart1 = 1,
    uart2 = 2,
};

pub const Parity = enum(c_int) {
    disable = 0, // UART_PARITY_DISABLE (8N1)
    even = 2, // UART_PARITY_EVEN (8E1)
    odd = 3, // UART_PARITY_ODD (8O1)
};

pub const UART_SCLK_DEFAULT: c_int = 4; // SOC_MOD_CLK_PLL_F80M
pub const UART_SCLK_XTAL: c_int = 9; // SOC_MOD_CLK_XTAL (40 MHz crystal)

pub const IdfUartConfig = extern struct {
    baud_rate: c_int = 115200,
    data_bits: c_int = 3, // UART_DATA_8_BITS
    parity: c_int = 0, // UART_PARITY_DISABLE
    stop_bits: c_int = 1, // UART_STOP_BITS_1
    flow_ctrl: c_int = 0, // UART_HW_FLOWCTRL_DISABLE
    rx_flow_ctrl_thresh: u8 = 122,
    _pad: [3]u8 = .{ 0, 0, 0 },
    source_clk: c_int = UART_SCLK_XTAL,
    flags: u32 = 0,
};

extern fn uart_param_config(uart_num: c_int, uart_config: *const IdfUartConfig) c_int;
extern fn uart_set_pin(uart_num: c_int, tx_io_num: c_int, rx_io_num: c_int, rts_io_num: c_int, cts_io_num: c_int) c_int;
extern fn uart_driver_install(uart_num: c_int, rx_buffer_size: c_int, tx_buffer_size: c_int, queue_size: c_int, uart_queue: ?*anyopaque, intr_alloc_flags: c_int) c_int;
extern fn uart_driver_delete(uart_num: c_int) c_int;
extern fn uart_write_bytes(uart_num: c_int, src: ?*const anyopaque, size: usize) c_int;
extern fn uart_read_bytes(uart_num: c_int, buf: ?*anyopaque, length: u32, ticks_to_wait: u32) c_int;
extern fn uart_flush_input(uart_num: c_int) c_int;
extern fn uart_get_buffered_data_len(uart_num: c_int, size: *usize) c_int;

// ============================================================================
// Host Test Mocks
// ============================================================================

var mock_rx_buffer: [128]u8 = undefined;
var mock_rx_head: usize = 0;
var mock_rx_tail: usize = 0;
var mock_bootloader_triggered: bool = false;

// Mock state for generic UartPort (ports 0, 1, 2)
const MOCK_BUF_SIZE: usize = 4096;
var mock_uart_tx_buffer: [3][MOCK_BUF_SIZE]u8 = undefined;
var mock_uart_tx_len: [3]usize = .{ 0, 0, 0 };
var mock_uart_rx_buffer: [3][MOCK_BUF_SIZE]u8 = undefined;
var mock_uart_rx_head: [3]usize = .{ 0, 0, 0 };
var mock_uart_rx_tail: [3]usize = .{ 0, 0, 0 };
var mock_uart_installed: [3]bool = .{ false, false, false };
var mock_uart_parity: [3]Parity = .{ .disable, .disable, .disable };

fn mock_esp_rom_uart_rx_one_char(c: *u8) callconv(.c) i32 {
    if (mock_rx_head != mock_rx_tail) {
        c.* = mock_rx_buffer[mock_rx_tail];
        mock_rx_tail = (mock_rx_tail + 1) % mock_rx_buffer.len;
        return 0; // Success
    }
    return -1; // FIFO empty
}

fn mock_esp_rom_uart_tx_one_char(_: u8) callconv(.c) void {}
fn mock_esp_rom_printf(_: [*:0]const u8, ...) callconv(.c) void {}

fn mock_uart_driver_install(uart_num: c_int, _: c_int, _: c_int, _: c_int, _: ?*anyopaque, _: c_int) callconv(.c) c_int {
    if (uart_num >= 0 and uart_num < 3) {
        mock_uart_installed[@intCast(uart_num)] = true;
        return 0;
    }
    return -1;
}

fn mock_uart_param_config(uart_num: c_int, cfg: *const IdfUartConfig) callconv(.c) c_int {
    if (uart_num >= 0 and uart_num < 3) {
        const idx: usize = @intCast(uart_num);
        mock_uart_parity[idx] = switch (cfg.parity) {
            2 => .even,
            3 => .odd,
            else => .disable,
        };
        return 0;
    }
    return -1;
}

fn mock_uart_set_pin(uart_num: c_int, _: c_int, _: c_int, _: c_int, _: c_int) callconv(.c) c_int {
    if (uart_num >= 0 and uart_num < 3) return 0;
    return -1;
}

fn mock_uart_driver_delete(uart_num: c_int) callconv(.c) c_int {
    if (uart_num >= 0 and uart_num < 3) {
        mock_uart_installed[@intCast(uart_num)] = false;
        return 0;
    }
    return -1;
}

fn mock_uart_write_bytes(uart_num: c_int, src: ?*const anyopaque, size: usize) callconv(.c) c_int {
    if (uart_num < 0 or uart_num >= 3 or src == null) return -1;
    const idx: usize = @intCast(uart_num);
    const bytes: [*]const u8 = @ptrCast(src.?);
    var count: usize = 0;
    while (count < size and mock_uart_tx_len[idx] < mock_uart_tx_buffer[idx].len) : (count += 1) {
        mock_uart_tx_buffer[idx][mock_uart_tx_len[idx]] = bytes[count];
        mock_uart_tx_len[idx] += 1;
    }
    return @intCast(count);
}

fn mock_uart_read_bytes(uart_num: c_int, buf: ?*anyopaque, length: u32, _: u32) callconv(.c) c_int {
    if (uart_num < 0 or uart_num >= 3 or buf == null) return -1;
    const idx: usize = @intCast(uart_num);
    const dst: [*]u8 = @ptrCast(buf.?);
    var count: usize = 0;
    while (count < length and mock_uart_rx_head[idx] != mock_uart_rx_tail[idx]) : (count += 1) {
        dst[count] = mock_uart_rx_buffer[idx][mock_uart_rx_tail[idx]];
        mock_uart_rx_tail[idx] = (mock_uart_rx_tail[idx] + 1) % mock_uart_rx_buffer[idx].len;
    }
    return @intCast(count);
}

fn mock_uart_flush_input(uart_num: c_int) callconv(.c) c_int {
    if (uart_num >= 0 and uart_num < 3) {
        const idx: usize = @intCast(uart_num);
        mock_uart_rx_head[idx] = 0;
        mock_uart_rx_tail[idx] = 0;
        return 0;
    }
    return -1;
}

fn mock_uart_get_buffered_data_len(uart_num: c_int, size: *usize) callconv(.c) c_int {
    if (uart_num >= 0 and uart_num < 3) {
        const idx: usize = @intCast(uart_num);
        const head = mock_uart_rx_head[idx];
        const tail = mock_uart_rx_tail[idx];
        if (head >= tail) {
            size.* = head - tail;
        } else {
            size.* = mock_uart_rx_buffer[idx].len - tail + head;
        }
        return 0;
    }
    return -1;
}

comptime {
    if (builtin.is_test) {
        @export(&mock_esp_rom_uart_rx_one_char, .{ .name = "esp_rom_uart_rx_one_char" });
        @export(&mock_esp_rom_uart_tx_one_char, .{ .name = "esp_rom_uart_tx_one_char" });
        @export(&mock_esp_rom_printf, .{ .name = "esp_rom_printf" });
        @export(&mock_uart_param_config, .{ .name = "uart_param_config" });
        @export(&mock_uart_set_pin, .{ .name = "uart_set_pin" });
        @export(&mock_uart_driver_install, .{ .name = "uart_driver_install" });
        @export(&mock_uart_driver_delete, .{ .name = "uart_driver_delete" });
        @export(&mock_uart_write_bytes, .{ .name = "uart_write_bytes" });
        @export(&mock_uart_read_bytes, .{ .name = "uart_read_bytes" });
        @export(&mock_uart_flush_input, .{ .name = "uart_flush_input" });
        @export(&mock_uart_get_buffered_data_len, .{ .name = "uart_get_buffered_data_len" });
    }
}

pub fn mockInjectRx(port: PortNumber, data: []const u8) void {
    const idx: usize = @intCast(@intFromEnum(port));
    for (data) |b| {
        mock_uart_rx_buffer[idx][mock_uart_rx_head[idx]] = b;
        mock_uart_rx_head[idx] = (mock_uart_rx_head[idx] + 1) % mock_uart_rx_buffer[idx].len;
    }
}

pub fn mockGetTx(port: PortNumber) []const u8 {
    const idx: usize = @intCast(@intFromEnum(port));
    return mock_uart_tx_buffer[idx][0..mock_uart_tx_len[idx]];
}

pub fn mockReset(port: PortNumber) void {
    const idx: usize = @intCast(@intFromEnum(port));
    mock_uart_tx_len[idx] = 0;
    mock_uart_rx_head[idx] = 0;
    mock_uart_rx_tail[idx] = 0;
    mock_uart_parity[idx] = .disable;
}

// ============================================================================
// Hardware Console UART Interface
// ============================================================================

pub const USB_SERIAL_JTAG_BASE: usize = 0x6000F000;
pub const USB_SERIAL_JTAG_EP1_REG: usize = USB_SERIAL_JTAG_BASE + 0x00;
pub const USB_SERIAL_JTAG_EP1_CONF_REG: usize = USB_SERIAL_JTAG_BASE + 0x04;
pub const USB_SERIAL_JTAG_SERIAL_OUT_EP_DATA_AVAIL: u32 = 1 << 2;

pub const UsbSerialJtagMmio = extern struct {
    ep1_fifo: u32,
    ep1_conf: u32,
};

pub inline fn getUsbSerialJtagMmio() *volatile UsbSerialJtagMmio {
    return @ptrFromInt(USB_SERIAL_JTAG_BASE);
}

pub const ConsoleUart = struct {
    /// Read one character non-blockingly from primary UART0 or secondary USB Serial/JTAG FIFO
    pub fn readByte() ?u8 {
        var byte: u8 = 0;
        if (esp_rom_uart_rx_one_char(&byte) == 0) {
            return byte;
        }
        if (comptime builtin.cpu.arch == .riscv32) {
            const usb = getUsbSerialJtagMmio();
            if ((usb.ep1_conf & USB_SERIAL_JTAG_SERIAL_OUT_EP_DATA_AVAIL) != 0) {
                return @truncate(usb.ep1_fifo);
            }
        }
        return null;
    }

    /// Transmit one byte over console UART
    pub fn writeByte(byte: u8) void {
        esp_rom_uart_tx_one_char(byte);
    }

    /// Transmit a string slice over console UART
    pub fn write(bytes: []const u8) void {
        for (bytes) |b| {
            writeByte(b);
        }
    }

    /// Print formatted string via ROM printf
    pub fn print(comptime fmt: [*:0]const u8, args: anytype) void {
        @call(.auto, esp_rom_printf, .{fmt} ++ args);
    }

    /// Reboot chip directly into the ROM serial download bootloader
    pub fn rebootToBootloader() void {
        if (builtin.is_test) {
            mock_bootloader_triggered = true;
            return;
        }
        if (comptime builtin.cpu.arch == .riscv32) {
            getLpAonMmio().sys_cfg = LP_AON_FORCE_DOWNLOAD_BOOT | LP_AON_HPSYS_SW_RESET;
        }
    }
};

// ============================================================================
// Generic Multi-Port Hardware UART Interface
// ============================================================================

pub const UartConfig = struct {
    baud_rate: u32 = 115200,
    parity: Parity = .disable,
    tx_pin: u8,
    rx_pin: u8,
    rx_buffer_size: usize = 1024,
    tx_buffer_size: usize = 512,
};

pub const UartError = error{
    ParamConfigFailed,
    SetPinFailed,
    DriverInstallFailed,
    WriteFailed,
    ReadFailed,
};

pub const UartPort = struct {
    port: PortNumber,

    pub inline fn msToTicks(ms: u32) u32 {
        if (ms == 0) return 0;
        return (ms + 9) / 10;
    }

    pub fn init(port: PortNumber, config: UartConfig) UartError!UartPort {
        const p_num = @intFromEnum(port);
        const idf_cfg = IdfUartConfig{
            .baud_rate = @intCast(config.baud_rate),
            .data_bits = 3,
            .parity = @intFromEnum(config.parity),
            .stop_bits = 1,
            .flow_ctrl = 0,
            .rx_flow_ctrl_thresh = 122,
            .source_clk = UART_SCLK_XTAL,
            .flags = 0,
        };

        if (uart_param_config(p_num, &idf_cfg) != 0) {
            return UartError.ParamConfigFailed;
        }

        if (uart_set_pin(p_num, config.tx_pin, config.rx_pin, -1, -1) != 0) {
            return UartError.SetPinFailed;
        }

        if (uart_driver_install(p_num, @intCast(config.rx_buffer_size), @intCast(config.tx_buffer_size), 0, null, 0) != 0) {
            return UartError.DriverInstallFailed;
        }

        return .{ .port = port };
    }

    pub fn deinit(self: *UartPort) void {
        _ = uart_driver_delete(@intFromEnum(self.port));
    }

    pub fn write(self: *UartPort, data: []const u8) usize {
        if (data.len == 0) return 0;
        const res = uart_write_bytes(@intFromEnum(self.port), data.ptr, data.len);
        if (res < 0) return 0;
        return @intCast(res);
    }

    pub fn writeByte(self: *UartPort, byte: u8) void {
        const b = [1]u8{byte};
        _ = self.write(&b);
    }

    pub fn read(self: *UartPort, buf: []u8, timeout_ms: u32) usize {
        if (buf.len == 0) return 0;
        const ticks = msToTicks(timeout_ms);
        const res = uart_read_bytes(@intFromEnum(self.port), buf.ptr, @intCast(buf.len), ticks);
        if (res < 0) return 0;
        return @intCast(res);
    }

    pub fn readByte(self: *UartPort, timeout_ms: u32) ?u8 {
        var byte: u8 = 0;
        const read_len = self.read((&byte)[0..1], timeout_ms);
        if (read_len == 1) return byte;
        return null;
    }

    pub fn flush(self: *UartPort) void {
        _ = uart_flush_input(@intFromEnum(self.port));
    }

    pub fn getBufferedDataLen(self: *UartPort) usize {
        var len: usize = 0;
        _ = uart_get_buffered_data_len(@intFromEnum(self.port), &len);
        return len;
    }
};

// ============================================================================
// Command Processor
// ============================================================================

pub const UpdateCommand = enum {
    none,
    reboot_bootloader,
};

pub inline fn checkUpdateCommand(byte: u8) UpdateCommand {
    return switch (byte) {
        'b', 'B', 'u', 'U' => .reboot_bootloader,
        else => .none,
    };
}

// ============================================================================
// Mock UART for Testing
// ============================================================================

pub const MockUart = struct {
    tx_buffer: [256]u8 = undefined,
    tx_len: usize = 0,
    rx_queue: [64]u8 = undefined,
    rx_head: usize = 0,
    rx_tail: usize = 0,

    pub fn init() MockUart {
        return .{};
    }

    pub fn reset(self: *MockUart) void {
        self.tx_len = 0;
        self.rx_head = 0;
        self.rx_tail = 0;
    }

    pub fn injectInput(self: *MockUart, input: []const u8) void {
        for (input) |b| {
            self.rx_queue[self.rx_head] = b;
            self.rx_head = (self.rx_head + 1) % self.rx_queue.len;
        }
    }

    pub fn readByte(self: *MockUart) ?u8 {
        if (self.rx_head != self.rx_tail) {
            const b = self.rx_queue[self.rx_tail];
            self.rx_tail = (self.rx_tail + 1) % self.rx_queue.len;
            return b;
        }
        return null;
    }

    pub fn writeByte(self: *MockUart, b: u8) void {
        if (self.tx_len < self.tx_buffer.len) {
            self.tx_buffer[self.tx_len] = b;
            self.tx_len += 1;
        }
    }

    pub fn write(self: *MockUart, bytes: []const u8) void {
        for (bytes) |b| {
            self.writeByte(b);
        }
    }

    pub fn getOutput(self: *const MockUart) []const u8 {
        return self.tx_buffer[0..self.tx_len];
    }
};

// ============================================================================
// Tests
// ============================================================================

test "update command character recognition" {
    try std.testing.expectEqual(UpdateCommand.reboot_bootloader, checkUpdateCommand('b'));
    try std.testing.expectEqual(UpdateCommand.reboot_bootloader, checkUpdateCommand('B'));
    try std.testing.expectEqual(UpdateCommand.reboot_bootloader, checkUpdateCommand('u'));
    try std.testing.expectEqual(UpdateCommand.reboot_bootloader, checkUpdateCommand('U'));
    try std.testing.expectEqual(UpdateCommand.none, checkUpdateCommand('x'));
}

test "mock uart queueing and draining" {
    var uart = MockUart.init();

    try std.testing.expect(uart.readByte() == null);

    uart.injectInput("ping");
    try std.testing.expectEqual(@as(u8, 'p'), uart.readByte().?);
    try std.testing.expectEqual(@as(u8, 'i'), uart.readByte().?);
    try std.testing.expectEqual(@as(u8, 'n'), uart.readByte().?);
    try std.testing.expectEqual(@as(u8, 'g'), uart.readByte().?);
    try std.testing.expect(uart.readByte() == null);

    uart.write("pong");
    try std.testing.expectEqualStrings("pong", uart.getOutput());
}

test "generic UartPort lifecycle and operations" {
    mockReset(.uart1);

    var port = try UartPort.init(.uart1, .{
        .baud_rate = 115200,
        .tx_pin = 21,
        .rx_pin = 20,
        .rx_buffer_size = 1024,
        .tx_buffer_size = 512,
    });
    defer port.deinit();

    const msg = "HELLO_ESP32";
    const written = port.write(msg);
    try std.testing.expectEqual(msg.len, written);
    try std.testing.expectEqualStrings(msg, mockGetTx(.uart1));

    const rx_msg = "ACK_FROM_PEER";
    mockInjectRx(.uart1, rx_msg);
    try std.testing.expectEqual(rx_msg.len, port.getBufferedDataLen());

    var rx_buf: [32]u8 = undefined;
    const read_bytes = port.read(&rx_buf, 10);
    try std.testing.expectEqual(rx_msg.len, read_bytes);
    try std.testing.expectEqualStrings(rx_msg, rx_buf[0..read_bytes]);
}

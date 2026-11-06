//! ESP32 Hardware Abstraction Layer (HAL)
//!
//! Pure silicon-level abstraction for ESP32 family SoCs.
//! Completely independent of any board layout or product application logic.
//!
//! Modules:
//! - gpio: Generic OutputPin, InputPin, direct MMIO registers, mock pins
//! - uart: Non-blocking console I/O, multi-port UART driver, ROM bootloader trigger
//! - delay: Bare-metal microsecond busy-wait delays via ROM routines
//! - system: Heap queries, reset control, uptime tracking

pub const gpio = @import("gpio.zig");
pub const uart = @import("uart.zig");
pub const delay = @import("delay.zig");
pub const system = @import("system.zig");

test {
    _ = gpio;
    _ = uart;
    _ = delay;
    _ = system;
}

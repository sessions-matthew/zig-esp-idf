# Zig + FreeRTOS + ESP-IDF Starter Template (`zig-esp-idf`)

A clean, standalone, and production-ready project template pairing **Zig 0.17.0** with **ESP-IDF v5.x** and **FreeRTOS**.

This repository contains the pure FreeRTOS abstractions and ESP32 silicon HAL extracted and decoupled from application-specific logic, ready to serve as the foundation for any new embedded Zig project on Espressif microcontrollers.

---

## Architecture Overview

```
zig-esp-idf/
├── CMakeLists.txt              # Top-level ESP-IDF CMake project definition
├── sdkconfig.defaults          # Default ESP-IDF configuration (ESP32-C6 / generic)
├── build.zig                   # Multi-target Zig 0.17 build script
├── build.zig.zon               # Zig package manifest
├── main/
│   ├── CMakeLists.txt          # ESP-IDF component CMake invoking 'zig build'
│   └── app_entry.c             # Minimal C anchor for component registration
├── src/
│   ├── main.zig                # Clean app_main() entry point demonstrating tasks & queues
│   ├── rtos/                   # Zero-overhead FreeRTOS abstractions & bindings
│   │   ├── root.zig            # Re-exports types, task, queue, mutex, critical
│   │   ├── types.zig           # Handles, base types, ticks/ms conversions, errors
│   │   ├── task.zig            # Task.spawn, delay, delayUntil, stack watermarks
│   │   ├── queue.zig           # Type-safe dynamic Queue(T) & static StaticQueue(T, N)
│   │   ├── mutex.zig           # Mutex with RAII lock guards (defer lock.release())
│   │   └── critical.zig        # Critical sections & CriticalGuard
│   └── hal/                    # ESP32 silicon Hardware Abstraction Layer
│       ├── root.zig            # Re-exports gpio, uart, delay, system
│       ├── uart.zig            # ConsoleUart (ROM printf), UartPort, bootloader reset
│       ├── gpio.zig            # OutputPin, InputPin, MMIO fast paths & mock pins
│       ├── delay.zig           # Microsecond busy-wait delays (esp_rom_delay_us)
│       └── system.zig          # Heap statistics, uptime counters, chip restart
└── scripts/
    └── build.sh                # Helper script for building, testing, flashing, and monitoring
```

---

## Key Features

1. **Pure Zig Application Logic (`src/main.zig`)**:
   - The entire firmware entry point (`app_main`), background tasks, and event loops are written in pure Zig.
   - Minimal C glue: `main/app_entry.c` is only a trivial 10-line anchor satisfying ESP-IDF's component build phase.

2. **Zero-Cost FreeRTOS Bindings (`src/rtos/`)**:
   - **`Task.spawn`**: Type-safe task spawning handling C trampolines automatically.
   - **`Queue(T)`**: Generic compile-time type-checked FIFO queues allocated from the FreeRTOS heap.
   - **`Mutex` & RAII Locks**: Ergonomic mutex locking via `const lock = try mutex.acquire(timeout); defer lock.release();`.
   - **`CriticalGuard`**: Exception-safe interrupt-disabling critical sections.

3. **Host-First Testability**:
   - All RTOS primitives and HAL drivers include built-in test mocks.
   - Run the complete unit test suite on macOS/Linux in milliseconds without needing hardware or ESP-IDF toolchains:
     ```bash
     zig build test --summary all
     ```

4. **Remote Bootloader Recovery**:
   - `hal.uart.ConsoleUart.rebootToBootloader()` triggers the ROM serial download bootloader via `LP_AON_SYS_CFG_REG`.
   - Incoming UART characters `'b'`, `'B'`, `'u'`, `'U'` trigger software download mode, allowing repeated flashing without physical button presses.

---

## Quick Start

### Prerequisites
- **Zig 0.17.0**: Installed and available in your `PATH`.
- **ESP-IDF v5.x**: Standard installation (e.g. at `~/esp/esp-idf`).

### Essential Commands

```bash
# 1. Run Host Unit Tests (Instant feedback, no hardware needed)
./scripts/build.sh test

# 2. Build the Complete ESP-IDF Firmware Binary
./scripts/build.sh build

# 3. Flash to Connected ESP32 Board over USB
./scripts/build.sh flash

# 4. Open Serial Monitor (115200 baud)
./scripts/build.sh monitor
```

---

## FreeRTOS Zig API Usage Guide

### 1. Spawning Tasks
```zig
const rtos = @import("rtos");

fn myWorkerTask(_: ?*anyopaque) void {
    while (true) {
        // Delay task for 1000 milliseconds
        rtos.Task.delayMs(1000);
    }
}

// In app_main or initialization:
const task = try rtos.Task.spawn(
    "worker",     // Task name
    4096,         // Stack size in bytes (ESP-IDF FreeRTOS uses bytes)
    5,            // Task priority
    myWorkerTask, // Entry function
    null,         // Parameter context
);
```

### 2. Typed Message Queues
```zig
const rtos = @import("rtos");

const SensorReading = struct {
    temperature: f32,
    humidity: f32,
};

// Create a queue holding up to 10 SensorReading items
var queue = try rtos.Queue(SensorReading).init(10);
defer queue.deinit();

// Producer task (timeout in milliseconds):
try queue.send(.{ .temperature = 23.5, .humidity = 48.0 }, 100);

// Consumer task (returns ?SensorReading):
if (queue.receive(500)) |reading| {
    // Process reading
}
```

### 3. Mutex with RAII Lock Guard
```zig
const rtos = @import("rtos");

var shared_mutex = try rtos.Mutex.create();
defer shared_mutex.deinit();

{
    // Acquire mutex with 100ms timeout
    const lock = try shared_mutex.acquire(100);
    defer lock.release(); // Lock automatically released when exiting block scope

    // Protected critical section
}
```

### 4. Non-Blocking Console UART & Formatted Printing
```zig
const hal = @import("hal");

// Formatted print using ESP ROM printf (zero allocation)
hal.uart.ConsoleUart.print("Free heap: %u bytes\n", .{hal.system.System.getFreeHeap()});

// Poll non-blockingly for console input
if (hal.uart.ConsoleUart.readByte()) |char| {
    if (char == 'b') {
        // Jump directly into ROM download bootloader for flashing
        hal.uart.ConsoleUart.rebootToBootloader();
    }
}
```

---

## How It Builds & Links

1. **`build.zig`** cross-compiles `src/main.zig` targeting `riscv32-freestanding-none` (`generic_rv32+m+a+c+zicsr+zifencei+relax`).
2. Zig emits a standalone relocatable ELF object:
   ```
   zig-out/lib/zig_esp_idf.o
   ```
3. ESP-IDF CMake (`main/CMakeLists.txt`) automatically invokes `zig build app-core` and links `zig_esp_idf.o` into `${COMPONENT_LIB}`:
   ```cmake
   target_sources(${COMPONENT_LIB} PRIVATE "${ZIG_OBJ}")
   ```
4. ESP-IDF links the complete binary image `build/zig_esp_idf.bin` with the FreeRTOS kernel, bootloader, partition table, and hardware drivers.

---

## Customizing Target Chip

To switch to a different target (e.g. `esp32c3`, `esp32s3`, `esp32`):
1. In `sdkconfig.defaults`: Change `CONFIG_IDF_TARGET="esp32c6"` to your desired chip.
2. In `build.zig`: Adjust the `arch_os_abi` and `cpu_features` in `esp32_target` (for Xtensa chips like ESP32/ESP32-S3, specify `xtensa-freestanding-none`).
3. Clean and reconfigure:
   ```bash
   ./scripts/build.sh clean
   idf.py set-target <target>
   ./scripts/build.sh build
   ```

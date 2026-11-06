# Zig + FreeRTOS + ESP-IDF Starter Template (`zig-esp-idf`)

[![Discord - Zig LLM Group](https://img.shields.io/badge/Discord-Zig%20LLM%20Group-5865F2?logo=discord&logoColor=white)](https://discord.gg/qs5gbtg28H)

A clean, standalone project template pairing **Zig 0.17.0** with **ESP-IDF v5.x** and **FreeRTOS**.

> **Community**: Join the [**Zig LLM Group** Discord server](https://discord.gg/qs5gbtg28H) to discuss Zig on microcontrollers, ESP-IDF integration, and AI agent workflows.

---

## Architecture Overview

```
zig-esp-idf/
├── CMakeLists.txt              # Top-level ESP-IDF CMake project definition
├── sdkconfig.defaults          # Default ESP-IDF configuration (ESP32-C6 / generic)
├── build.zig                   # Native Zig 0.17 build & toolchain orchestration
├── build.zig.zon               # Zig package manifest
├── main/
│   ├── CMakeLists.txt          # ESP-IDF component linking zig-out/lib/zig_esp_idf.o
│   └── app_entry.c             # Minimal C anchor satisfying component registration
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
└── README.md                   # Project documentation
```

---

## Commands

| Command | Action |
| :--- | :--- |
| `zig build` | Compiles the Zig object and builds the complete ESP-IDF binary (`build/zig_esp_idf.bin`) |
| `zig build test --summary all` | Runs all host unit tests natively (sub-second, 0 hardware required) |
| `zig build flash` | Flashes firmware to the board (auto-detects USB port) |
| `zig build flash -Dport=/dev/cu.usbmodem11301` | Flashes to a specific serial port |
| `zig build monitor` | Opens the interactive serial console monitor |
| `zig build flash monitor` | Flashes and immediately connects to the serial console |
| `zig build app-core` | Compiles only the freestanding Zig object (RISC-V 32 via native LLVM) |
| `zig build app-core -Darch=xtensa` | Compiles for Xtensa (ESP32/ESP32-S3) via Zig C backend + ESP-IDF GCC |
| `zig build clean` | Cleans all build artifacts and caches |

---

## Dual Compilation Pipeline (RISC-V & Xtensa)

`build.zig` dynamically adapts to the target architecture:

1. **RISC-V Targets (ESP32-C3, ESP32-C6, ESP32-H2)**:
   - Compiles directly to ELF relocatable objects (`zig-out/lib/zig_esp_idf.o`) using Zig's built-in LLVM backend.
2. **Xtensa Targets (ESP32 classic, ESP32-S2, ESP32-S3)**:
   - Uses Zig's C backend (`-ofmt=c`) to translate Zig into standard C (`zig-out/src/zig_esp_idf.c`).
   - Automatically invokes ESP-IDF's bundled `xtensa-esp-elf-gcc` to produce the final `zig-out/lib/zig_esp_idf.o`.
   - ESP-IDF CMake automatically passes `-Darch=xtensa` when `IDF_TARGET` is set to an Xtensa chip.

---

## Key Features

1. **Pure Zig Application Logic (`src/main.zig`)**:
   - The entire firmware entry point (`app_main`), background tasks, and event loops are written in pure Zig.
   - Minimal C glue: `main/app_entry.c` is only a trivial anchor satisfying ESP-IDF's component build phase.

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
   zig build clean
   idf.py set-target <target>
   zig build
   ```

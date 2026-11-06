const std = @import("std");

pub const TargetArch = enum {
    riscv32,
    xtensa,
};

fn makeIdfCommand(b: *std.Build, subcmd: []const u8, port: ?[]const u8) *std.Build.Step.Run {
    var cmd_buf: std.ArrayList(u8) = .empty;
    defer cmd_buf.deinit(b.allocator);

    cmd_buf.appendSlice(b.allocator,
        \\if ! command -v idf.py >/dev/null 2>&1; then source ${HOME}/esp/esp-idf/export.sh >/dev/null 2>&1; fi
        \\PORT=""
    ) catch @panic("OOM");

    if (port) |p| {
        cmd_buf.appendSlice(b.allocator, "\nPORT=\"") catch @panic("OOM");
        cmd_buf.appendSlice(b.allocator, p) catch @panic("OOM");
        cmd_buf.appendSlice(b.allocator, "\"\n") catch @panic("OOM");
    } else {
        cmd_buf.appendSlice(b.allocator,
            \\
            \\for candidate in /dev/cu.usbmodem* /dev/ttyACM* /dev/ttyUSB*; do
            \\  if [[ -e "$candidate" ]]; then PORT="$candidate"; break; fi
            \\done
            \\
        ) catch @panic("OOM");
    }

    cmd_buf.appendSlice(b.allocator,
        \\if [[ -n "$PORT" ]]; then
        \\  exec idf.py -p "$PORT" 
    ) catch @panic("OOM");
    cmd_buf.appendSlice(b.allocator, subcmd) catch @panic("OOM");
    cmd_buf.appendSlice(b.allocator,
        \\
        \\else
        \\  exec idf.py 
    ) catch @panic("OOM");
    cmd_buf.appendSlice(b.allocator, subcmd) catch @panic("OOM");
    cmd_buf.appendSlice(b.allocator, "\nfi\n") catch @panic("OOM");

    const full_cmd = cmd_buf.toOwnedSlice(b.allocator) catch @panic("OOM");
    const run_cmd = b.addSystemCommand(&.{ "bash", "-c", full_cmd });
    run_cmd.stdio = .inherit;
    run_cmd.has_side_effects = true;
    return run_cmd;
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const port = b.option([]const u8, "port", "Serial port for flashing and monitoring (e.g. -Dport=/dev/cu.usbmodem11301)");
    const arch_opt = b.option(TargetArch, "arch", "Target architecture: riscv32 (default: native LLVM) or xtensa (Zig C backend + GCC)");
    const force_c_backend = b.option(bool, "c-backend", "Force using the Zig C backend + ESP-IDF GCC toolchain") orelse false;

    const is_xtensa = (arch_opt == .xtensa);
    const use_c_backend = is_xtensa or force_c_backend;

    // ------------------------------------------------------------------------
    // Target 1: ESP32 Silicon Target (RISC-V 32 or Xtensa)
    // ------------------------------------------------------------------------
    const esp32_target = if (is_xtensa)
        b.resolveTargetQuery(.{
            .cpu_arch = .xtensa,
            .cpu_model = .{ .explicit = &std.Target.xtensa.cpu.esp32 },
            .os_tag = .freestanding,
            .ofmt = if (use_c_backend) .c else null,
        })
    else
        b.resolveTargetQuery(
            std.Target.Query.parse(.{
                .arch_os_abi = "riscv32-freestanding-none",
                .cpu_features = "generic_rv32+m+a+c+zicsr+zifencei+relax",
            }) catch unreachable,
        );

    const hal_mod = b.createModule(.{
        .root_source_file = b.path("src/hal/root.zig"),
        .target = esp32_target,
        .optimize = optimize,
    });

    const rtos_mod = b.createModule(.{
        .root_source_file = b.path("src/rtos/root.zig"),
        .target = esp32_target,
        .optimize = optimize,
    });

    const app_core_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = esp32_target,
        .optimize = optimize,
        .strip = false,
        .imports = &.{
            .{ .name = "hal", .module = hal_mod },
            .{ .name = "rtos", .module = rtos_mod },
        },
    });

    const app_obj = b.addObject(.{
        .name = "zig_esp_idf",
        .root_module = app_core_mod,
    });

    // Step for compiling the Zig core object
    const app_core_step = b.step("app-core", "Build ESP32 Zig core object only (zig-out/lib/zig_esp_idf.o)");

    // Dependency step for IDF build
    var obj_ready_step: *std.Build.Step = undefined;

    if (use_c_backend) {
        // Model A: Zig emits C code, then ESP-IDF GCC compiles it into an ELF object
        const install_c_source = b.addInstallFile(app_obj.getEmittedBin(), "src/zig_esp_idf.c");

        const gcc_tool = if (is_xtensa) "xtensa-esp-elf-gcc" else "riscv32-esp-elf-gcc";
        const compile_script = b.fmt(
            \\if ! command -v {s} >/dev/null 2>&1; then source ${{HOME}}/esp/esp-idf/export.sh >/dev/null 2>&1; fi
            \\ZIG_LIB_DIR="$(zig env | grep lib_dir | awk '{{print $3}}' | tr -d '",')"
            \\mkdir -p zig-out/lib
            \\{s} -c zig-out/src/zig_esp_idf.c -I"${{ZIG_LIB_DIR}}" "-D_Static_assert(x,y)=" -O2 -ffunction-sections -fdata-sections -mlongcalls -o zig-out/lib/zig_esp_idf.o
        , .{ gcc_tool, gcc_tool });

        const gcc_compile_cmd = b.addSystemCommand(&.{ "bash", "-c", compile_script });
        gcc_compile_cmd.step.dependOn(&install_c_source.step);
        gcc_compile_cmd.stdio = .inherit;
        gcc_compile_cmd.has_side_effects = true;

        app_core_step.dependOn(&gcc_compile_cmd.step);
        obj_ready_step = &gcc_compile_cmd.step;
    } else {
        // Model B: Native Zig LLVM code generation (RISC-V 32)
        const install_app_obj = b.addInstallFile(app_obj.getEmittedBin(), "lib/zig_esp_idf.o");
        app_core_step.dependOn(&install_app_obj.step);
        obj_ready_step = &install_app_obj.step;
    }

    // ------------------------------------------------------------------------
    // Target 2: Host Unit Testing (`zig build test --summary all`)
    // ------------------------------------------------------------------------
    const host_target = b.resolveTargetQuery(.{});

    const host_hal_mod = b.createModule(.{
        .root_source_file = b.path("src/hal/root.zig"),
        .target = host_target,
        .optimize = optimize,
    });

    const host_rtos_mod = b.createModule(.{
        .root_source_file = b.path("src/rtos/root.zig"),
        .target = host_target,
        .optimize = optimize,
    });

    const host_app_core_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = host_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "hal", .module = host_hal_mod },
            .{ .name = "rtos", .module = host_rtos_mod },
        },
    });

    const unit_tests = b.addTest(.{
        .root_module = host_app_core_mod,
    });

    const hal_tests = b.addTest(.{
        .root_module = host_hal_mod,
    });

    const rtos_tests = b.addTest(.{
        .root_module = host_rtos_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_hal_tests = b.addRunArtifact(hal_tests);
    const run_rtos_tests = b.addRunArtifact(rtos_tests);

    const test_step = b.step("test", "Run unit tests on host platform (pure Zig, 0 hardware)");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_hal_tests.step);
    test_step.dependOn(&run_rtos_tests.step);

    // ------------------------------------------------------------------------
    // Target 3: ESP-IDF Toolchain Steps (`zig build`, `zig build flash`, etc.)
    // ------------------------------------------------------------------------
    const idf_build_cmd = makeIdfCommand(b, "build", null);
    idf_build_cmd.step.dependOn(obj_ready_step);

    const idf_step = b.step("idf", "Build complete ESP-IDF firmware binary (build/zig_esp_idf.bin)");
    idf_step.dependOn(&idf_build_cmd.step);

    // Default 'zig build' builds the complete ESP-IDF binary
    b.default_step.dependOn(idf_step);

    // Flash step: 'zig build flash [-Dport=...]'
    const flash_cmd = makeIdfCommand(b, "flash", port);
    flash_cmd.step.dependOn(&idf_build_cmd.step);
    const flash_step = b.step("flash", "Flash firmware binary to ESP32 over USB");
    flash_step.dependOn(&flash_cmd.step);

    // Monitor step: 'zig build monitor [-Dport=...]'
    const monitor_cmd = makeIdfCommand(b, "monitor", port);
    const monitor_step = b.step("monitor", "Open interactive serial console monitor");
    monitor_step.dependOn(&monitor_cmd.step);

    // Clean step: 'zig build clean'
    const clean_cmd = b.addSystemCommand(&.{
        "rm", "-rf", "build", ".zig-cache", "zig-out", "sdkconfig.old",
    });
    clean_cmd.has_side_effects = true;
    const clean_step = b.step("clean", "Remove all build artifacts and caches");
    clean_step.dependOn(&clean_cmd.step);
}

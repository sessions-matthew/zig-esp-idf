const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // ------------------------------------------------------------------------
    // Target 1: ESP32 (RISC-V 32-bit RV32IMAC for ESP32-C6 / ESP32-C3)
    // ------------------------------------------------------------------------
    const esp32_target = b.resolveTargetQuery(
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

    const install_app_obj = b.addInstallFile(app_obj.getEmittedBin(), "lib/zig_esp_idf.o");
    b.getInstallStep().dependOn(&install_app_obj.step);

    const app_core_step = b.step("app-core", "Build ESP32 Zig core object");
    app_core_step.dependOn(&install_app_obj.step);

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

    const test_step = b.step("test", "Run unit tests on host platform");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_hal_tests.step);
    test_step.dependOn(&run_rtos_tests.step);

    // ------------------------------------------------------------------------
    // Target 3: ESP-IDF Build Step (`zig build idf`)
    // ------------------------------------------------------------------------
    const idf_step = b.step("idf", "Build complete ESP-IDF firmware binary");
    const run_idf_build = b.addSystemCommand(&.{
        "bash", "-c", "source ${HOME}/esp/esp-idf/export.sh 2>/dev/null && idf.py build",
    });
    run_idf_build.step.dependOn(&install_app_obj.step);
    idf_step.dependOn(&run_idf_build.step);
}

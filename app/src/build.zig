const std = @import("std");
const builtin = std.builtin;
const Build = std.Build;
const Target = std.Target;
const arm = Target.arm;
const SemanticVersion = std.SemanticVersion;

const OUTPUT_DIR: []const u8 = "../build";
const TARGET_SOC: Target.Cpu.Model = arm.cpu.cortex_m33;
const VER: []const u8 = "0.1.0";
const SEMANTIC_VER: SemanticVersion = SemanticVersion.parse(VER) catch unreachable;
const APP_ENTRY_FILE: []const u8 = "zig/main.zig";

pub fn build(b: *Build) void {
    b.lib_dir = OUTPUT_DIR;
    b.exe_dir = OUTPUT_DIR;

    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .Debug });

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &TARGET_SOC },
        .abi = .eabi,
        .os_tag = .freestanding,
    });

    const trim = if (optimize != .Debug) true else false;

    const module = b.createModule(.{
        .root_source_file = b.path(APP_ENTRY_FILE),
        .optimize = optimize,
        .target = target,
        .code_model = .small,
        .strip = trim,
        .omit_frame_pointer = trim,
    });

    const app = b.addLibrary(.{
        .name = "app",
        .linkage = .static,
        .version = SEMANTIC_VER,
        .root_module = module,
    });

    b.installArtifact(app);
}

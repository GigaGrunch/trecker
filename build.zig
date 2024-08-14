const std = @import("std");

comptime {
    const zig_version = .{ .major = 0, .minor = 13, .patch = 0 };
    const compatible = @import("builtin").zig_version.order(zig_version) == .eq;
    // TODO: use comptime-print
    var buffer: [100]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    stream.writer().print("Zig version {d}.{d}.{d} is required.", .{ zig_version.major, zig_version.minor, zig_version.patch }) catch @compileError("Failed to print compile error.");
    if (!compatible) @compileError(&buffer);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "trecker",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const flags = b.dependency("flags", .{});
    exe.root_module.addImport("flags", flags.module("flags"));

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

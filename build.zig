const std = @import("std");

comptime {
    const expected_zig_version = .{ .major = 0, .minor = 12, .patch = 0 };
    const compatible = @import("builtin").zig_version.order(expected_zig_version) == .eq;
    if (!compatible) @compileError("Zig version 0.12.0 is required.");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (false)
    {const exe = b.addExecutable(.{
            .name = "trecker",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
    
        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
    
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);}

    const checker = b.addExecutable(.{
        .name = "checker",
        .root_source_file = .{ .path = "src/checker.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(checker);
    const checker_cmd = b.addRunArtifact(checker);
    checker_cmd.step.dependOn(b.getInstallStep());

    const checker_step = b.step("checker", "Checker");
    checker_step.dependOn(&checker_cmd.step);
}

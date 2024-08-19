const std = @import("std");

comptime {
    const zig_version = .{ .major = 0, .minor = 13, .patch = 0 };
    const compatible = @import("builtin").zig_version.order(zig_version) == .eq;
    const message = std.fmt.comptimePrint("Zig version {d}.{d}.{d} is required.", .{ zig_version.major, zig_version.minor, zig_version.patch });
    if (!compatible) @compileError(message);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const git_commit_hash = parseGitCommitHash();
    const build_info = b.addOptions();
    build_info.addOption([]const u8, "git_commit_hash", git_commit_hash);

    const exe = b.addExecutable(.{
        .name = "trecker",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addOptions("build_info", build_info);

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

var git_commit_hash_buffer: [40]u8 = undefined;
fn parseGitCommitHash() []const u8 {
    return std.fmt.comptimePrint("unknown git commit hash", .{});
}

// 9d74ed9bea9286c2f174995760c1a12f7b374589

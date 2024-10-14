const std = @import("std");
const builtin = @import("builtin");
const allocator_compatibility = @import("src/allocator_compatibility.zig");

comptime {
    const zig_version = .{ .major = 0, .minor = 13, .patch = 0 };
    const compatible = builtin.zig_version.order(zig_version) == .eq;
    const message = std.fmt.comptimePrint("Zig version {d}.{d}.{d} is required.", .{ zig_version.major, zig_version.minor, zig_version.patch });
    if (!compatible) @compileError(message);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const allocator_type: enum { gpa, c } = switch (optimize) {
        .Debug => .gpa,
        .ReleaseSafe => .c,
        .ReleaseFast => .c,
        .ReleaseSmall => .c,
    };

    const build_info = b.addOptions();
    build_info.addOption([]const u8, "git_commit_hash", parseGitCommitHash(b));
    build_info.addOption(std.SemanticVersion, "zig_version", builtin.zig_version);
    build_info.addOption(@TypeOf(allocator_type), "allocator_type", allocator_type);

    const exe = b.addExecutable(.{
        .name = "trecker",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    switch (allocator_type) {
        .gpa => {},
        .c => exe.linkLibC(),
    }

    exe.root_module.addOptions("build_info", build_info);

    const flags = b.dependency("flags", .{});
    exe.root_module.addImport("flags", flags.module("flags"));

    const zeit = b.dependency("zeit", .{});
    exe.root_module.addImport("zeit", zeit.module("zeit"));

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn parseGitCommitHash(b: *std.Build) []const u8 {
    const fallback = std.fmt.comptimePrint("unknown git commit hash", .{});

    var git_root = b.build_root.handle.openDir(".git", .{}) catch return fallback;
    defer git_root.close();

    const head_text = git_root.readFileAlloc(b.allocator, "HEAD", 1000) catch return fallback;

    var head_text_it = std.mem.tokenize(u8, head_text, " \r\n");
    const head_key = head_text_it.next() orelse return fallback;
    if (!std.mem.eql(u8, head_key, "ref:")) return fallback;
    const head_value = head_text_it.next() orelse return fallback;

    const ref_text = git_root.readFileAlloc(b.allocator, head_value, 1000) catch return fallback;

    var ref_text_it = std.mem.tokenize(u8, ref_text, "\r\n");
    const ref_value = ref_text_it.next() orelse return fallback;

    return b.allocator.dupe(u8, ref_value) catch return fallback;
}

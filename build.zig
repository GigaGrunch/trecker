const std = @import("std");

comptime {
    const zig_version = .{ .major = 0, .minor = 13, .patch = 0 };
    const compatible = @import("builtin").zig_version.order(zig_version) == .eq;
    const message = std.fmt.comptimePrint("Zig version {d}.{d}.{d} is required.", .{ zig_version.major, zig_version.minor, zig_version.patch });
    if (!compatible) @compileError(message);
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const git_commit_hash = parseGitCommitHash(b);
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

var git_commit_hash_buffer = [_]u8 {0} ** 40;
fn parseGitCommitHash(b: *std.Build) []const u8 {
    const fallback = std.fmt.comptimePrint("unknown git commit hash", .{});

    const head_path = b.pathFromRoot(".git/HEAD");

    const head_file = std.fs.openFileAbsolute(head_path, .{}) catch return fallback;
    var head_text_buffer: [1000]u8 = undefined;
    const head_text_len = head_file.readAll(head_text_buffer[0..]) catch return fallback;
    const head_text = head_text_buffer[0..head_text_len];

    var head_text_it = std.mem.tokenize(u8, head_text, " \r\n");

    const head_key = head_text_it.next() orelse return fallback;
    if (!std.mem.eql(u8, head_key, "ref:")) return fallback;

    const head_value = head_text_it.next() orelse return fallback;

    var ref_path_buffer = [_]u8 {0} ** 1000;
    var ref_path_stream = std.io.fixedBufferStream(&ref_path_buffer);
    ref_path_stream.writer().print(".git/{s}", .{head_value}) catch return fallback;
    const ref_path = b.pathFromRoot(ref_path_buffer[0..]);

    const ref_file = std.fs.openFileAbsolute(ref_path, .{}) catch return fallback;
    var ref_text_buffer: [1000]u8 = undefined;
    const ref_text_len = ref_file.readAll(ref_text_buffer[0..]) catch return fallback;
    const ref_text = ref_text_buffer[0..ref_text_len];

    var ref_text_it = std.mem.tokenize(u8, ref_text, "\r\n");
    const ref_value = ref_text_it.next() orelse return fallback;

    var git_commit_hash_stream = std.io.fixedBufferStream(&git_commit_hash_buffer);
    git_commit_hash_stream.writer().print("{s}", .{ref_value}) catch return fallback;
    return git_commit_hash_buffer[0..];
}

// 9d74ed9bea9286c2f174995760c1a12f7b374589

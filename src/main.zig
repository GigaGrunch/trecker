const std = @import("std");
const flags = @import("flags");
const commands = @import("commands.zig");
const Args = @import("Args.zig");

const use_gpa = @import("builtin").mode == .Debug;

pub fn main() !void {
    var alloc_wrapper = getAllocWrapper();
    defer deinitAllocWrapper(&alloc_wrapper);
    const allocator = getAllocator(&alloc_wrapper);

    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();

    const args = flags.parse(&args_it, Args, .{});
    try switch (args.command) {
        .init => commands.init(allocator),
        .start => |sub_args| commands.start(allocator, sub_args.positional.project_id),
        .add => |sub_args| commands.add(allocator, sub_args.positional.project_id, sub_args.positional.project_name),
        .list => commands.list(allocator),
        .summary => |sub_args| commands.summary(allocator, sub_args.positional.month, sub_args.positional.year),
        .version => commands.version(),
    };
}

const AllocWrapper = if (use_gpa) std.heap.GeneralPurposeAllocator(.{}) else void;

fn getAllocWrapper() AllocWrapper {
    return if (use_gpa) .{} else {};
}

fn deinitAllocWrapper(alloc_wrapper: *AllocWrapper) void {
    if (use_gpa) {
        _ = alloc_wrapper.deinit();
    }
}

fn getAllocator(alloc_wrapper: *AllocWrapper) std.mem.Allocator {
    return if (use_gpa) alloc_wrapper.allocator() else std.heap.c_allocator;
}

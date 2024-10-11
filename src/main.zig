const std = @import("std");
const flags = @import("flags");
const commands = @import("commands.zig");
const util = @import("util.zig");
const Store = @import("Store.zig");
const Timestamp = @import("Timestamp.zig");
const Args = @import("Args.zig");

pub fn main() !void {
    var gpa = if (use_gpa) std.heap.GeneralPurposeAllocator(.{}){} else @as(std.heap.GeneralPurposeAllocator(.{}), undefined);
    defer _ = if (use_gpa) gpa.deinit() else undefined;
    const allocator = if (use_gpa) gpa.allocator() else std.heap.c_allocator;

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

const allocator_option = @import("build_options").allocator;
const use_gpa = blk: {
    if (std.mem.eql(u8, allocator_option, "gpa")) {
        break :blk true;
    }
    if (std.mem.eql(u8, allocator_option, "c")) {
        break :blk false;
    }
    unreachable;
};

const std = @import("std");
const flags = @import("flags");
const commands = @import("commands.zig");
const util = @import("util.zig");
const Store = @import("Store.zig");
const Timestamp = @import("Timestamp.zig");
const Args = @import("Args.zig");

pub fn main() !void {
    // TODO: Windows 11 does not allow GPA when building for release.
    // TODO: When this is fixed, remove linkLibC from build.zig as well.
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();
    const allocator = std.heap.c_allocator;

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

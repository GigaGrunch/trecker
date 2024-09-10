const std = @import("std");
const flags = @import("flags");
const Store = @import("Store.zig");
const Timestamp = @import("Timestamp.zig");
const Args = @import("Args.zig");
const commands = @import("commands.zig");
const util = @import("util.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

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

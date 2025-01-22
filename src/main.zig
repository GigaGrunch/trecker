const std = @import("std");
const commands = @import("commands.zig");
const Args = @import("Args.zig");

pub fn main() !void {
    var alloc_wrapper = getAllocWrapper();
    defer deinitAllocWrapper(&alloc_wrapper);
    const allocator = getAllocator(&alloc_wrapper);

    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();

    const parsed_args = Args.parseOrExit(&args_it);
    try switch (parsed_args.command) {
        .init => commands.init(allocator),
        .start => |sub_args| commands.start(allocator, sub_args.project_id),
        .add => |sub_args| commands.add(allocator, sub_args.project_id, sub_args.project_name),
        .list => commands.list(allocator),
        .summary => |sub_args| commands.text_summary(allocator, sub_args.month, sub_args.year),
        .csv => |sub_args| commands.csv_summary(allocator, sub_args.month, sub_args.year, sub_args.user_name),
        .version => commands.version(),
    };
}

pub const allocator_type = @import("build_info").allocator_type;

const AllocWrapper = switch (allocator_type) {
    .gpa => std.heap.GeneralPurposeAllocator(.{}),
    .c => void,
};

pub fn getAllocWrapper() AllocWrapper {
    return switch (allocator_type) {
        .gpa => .{},
        .c => {},
    };
}

pub fn deinitAllocWrapper(alloc_wrapper: *AllocWrapper) void {
    switch (allocator_type) {
        .gpa => _ = alloc_wrapper.deinit(),
        .c => {},
    }
}

pub fn getAllocator(alloc_wrapper: *AllocWrapper) std.mem.Allocator {
    return switch (allocator_type) {
        .gpa => alloc_wrapper.allocator(),
        .c => std.heap.c_allocator,
    };
}

const std = @import("std");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const result = try std.ChildProcess.run(.{
        .allocator = allocator,
        .argv = args[1..],
    });

    return switch (result.term) {
        .Signal => 100,
        .Exited => |code| switch (code) {
            0 => 99,
            5 => 0,
            else => code,
        },
        .Stopped => 101,
        .Unknown => 102,
    };
}

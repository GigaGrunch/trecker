const std = @import("std");

const exe_name = "trecker";
pub const session_file_name = exe_name ++ "_session.ini";

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn float(int: anytype) f64 {
    return @floatFromInt(int);
}

const std = @import("std");
const zeit = @import("zeit");
const Timestamp = @This();

pub const Day = u5;
pub const Month = zeit.Month;

time: zeit.Time,

pub fn now(allocator: std.mem.Allocator) !Timestamp {
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    const local = try zeit.local(allocator, &env);
    defer local.deinit();

    const instant = try zeit.instant(.{});
    const now_local = instant.in(&local);

    return .{ .time = now_local.time() };
}

pub fn fromString(string: []const u8) !Timestamp {
    return .{ .time = try zeit.Time.fromISO8601(string) };
}

const string_length = "YYYY-MM-DDTHH:MM:SS".len;
pub fn toString(timestamp: *const Timestamp) ![string_length]u8 {
    var full_string_buffer: [100]u8 = undefined;
    var string_buffer: [string_length]u8 = undefined;
    const result = try timestamp.time.bufPrint(&full_string_buffer, .rfc3339);
    @memcpy(&string_buffer, result[0..string_buffer.len]);
    return string_buffer;
}

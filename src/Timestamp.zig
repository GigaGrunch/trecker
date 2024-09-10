const std = @import("std");
const Timestamp = @This();

const Year = u16;
const Month = u4;
pub const Day = u5;
const Hour = u5;
const Minute = u6;
const Second = u6;

year: Year,
month: Month,
day: Day,
hour: Hour,
minute: Minute,
second: Second,

pub fn now() Timestamp {
    const epoch_seconds = std.time.timestamp();
    return fromEpochSeconds(@intCast(epoch_seconds));
}

fn fromEpochSeconds(seconds: u64) Timestamp {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = seconds };
    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return .{
        .year = year_day.year,
        .month = month_day.month.numeric(),
        .day = 1 + month_day.day_index,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
    };
}

const string_len = "1993-04-06_17-00-00".len;
pub fn toString(t: Timestamp) [string_len]u8 {
    var buffer: [string_len]u8 = undefined;
    _ = std.fmt.bufPrint(&buffer, "{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}-{d:0>2}-{d:0>2}", .{ t.year, t.month, t.day, t.hour, t.minute, t.second }) catch unreachable;
    return buffer;
}

pub fn fromString(str: []const u8) !Timestamp {
    var it = std.mem.tokenize(u8, str, "-_");
    return .{
        .year = try std.fmt.parseInt(u16, it.next().?, 10),
        .month = try std.fmt.parseInt(u4, it.next().?, 10),
        .day = try std.fmt.parseInt(u5, it.next().?, 10),
        .hour = try std.fmt.parseInt(u5, it.next().?, 10),
        .minute = try std.fmt.parseInt(u6, it.next().?, 10),
        .second = try std.fmt.parseInt(u6, it.next().?, 10),
    };
}

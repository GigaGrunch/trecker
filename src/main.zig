const std = @import("std");

const exe_name = "trecker";

var projects: []Project = undefined;
var entries: []Entry = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();
    _ = args_it.skip(); // first arg is the exe's name
    const command = args_it.next() orelse {
        std.debug.print("Usage: " ++ exe_name ++ " <command> [args...]\n", .{});
        std.debug.print("    Commands: start, add, list, summary\n", .{});
        return;
    };

    defer {
        for (projects) |project| {
            project.deinit(allocator);
        }
        allocator.free(projects);
        for (entries) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(entries);
    }

    if (std.mem.eql(u8, command, "start")) {
        try executeStartCommand(allocator, &args_it);
    } else if (std.mem.eql(u8, command, "add")) {
        try executeAddCommand(allocator, &args_it);
    } else if (std.mem.eql(u8, command, "list")) {
        try executeListCommand(allocator);
    } else if (std.mem.eql(u8, command, "summary")) {
        try executeSummaryCommand(allocator, &args_it);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
    }
}

fn executeSummaryCommand(allocator: std.mem.Allocator, args_it: *std.process.ArgIterator) !void {
    const usage = "Usage: " ++ exe_name ++ " summary <month> <year>\n";
    const month_str = args_it.next() orelse {
        std.debug.print(usage, .{});
        return;
    };
    const year_str = args_it.next() orelse {
        std.debug.print(usage, .{});
        return;
    };

    const month_names: []const []const u8 = &.{
        "january",
        "february",
        "march",
        "april",
        "may",
        "june",
        "july",
        "august",
        "september",
        "october",
        "november",
        "december",
    };
    const month: u4 = for (month_names, 1..) |month_name, number| {
        if (std.mem.eql(u8, month_str, month_name)) {
            break @intCast(number);
        }
    } else {
        std.debug.print("Unknown month: '{s}'\n", .{month_str});
        return;
    };

    const year = try std.fmt.parseInt(u16, year_str, 10);

    try deserialize(allocator, .{});

    var project_hours = try allocator.alloc(struct { *Project, f64 }, projects.len);
    defer allocator.free(project_hours);
    for (projects, project_hours) |*project, *hours| {
        hours[0] = project;
        hours[1] = 0;
    }

    var total_hours: f64 = 0;
    var work_days: [31]Day = undefined;
    var work_days_len: usize = 0;

    for (entries) |entry| {
        if (entry.start.month != month) continue;
        if (entry.start.year != year) continue;

        if (std.mem.indexOfScalar(Day, work_days[0..work_days_len], entry.start.day) == null) {
            work_days[work_days_len] = entry.start.day;
            work_days_len += 1;
        }

        const project_index = for (projects, 0..) |project, i| {
            if (std.mem.eql(u8, project.id, entry.project_id)) break i;
        } else unreachable;

        const hours = entry.getHours();
        project_hours[project_index][1] += hours;
        total_hours += hours;
    }

    const avg_hours_per_day = total_hours / float(work_days_len);

    std.mem.sort(struct { *Project, f64 }, project_hours, {}, moreHours);

    std.debug.print("Total: {d:.2} hours ({d:.2} hours per day)\n", .{ total_hours, avg_hours_per_day });
    for (project_hours) |hours| {
        std.debug.print("{s}: {d:.2} hours ({d:.0} %)\n", .{ hours[0].name, hours[1], 100.0 * hours[1] / total_hours });
    }
}

fn moreHours(context: void, lhs: struct { *Project, f64 }, rhs: struct { *Project, f64 }) bool {
    _ = context;
    return lhs[1] > rhs[1];
}

fn executeAddCommand(allocator: std.mem.Allocator, args_it: *std.process.ArgIterator) !void {
    const usage = "Usage: " ++ exe_name ++ " add <project_it> <project_name>\n";
    const project_id = args_it.next() orelse {
        std.debug.print(usage, .{});
        return;
    };
    const project_name = args_it.next() orelse {
        std.debug.print(usage, .{});
        return;
    };

    try deserialize(allocator, .{ .extra_project = true });

    projects[projects.len - 1] = .{
        .id = try allocator.dupe(u8, project_id),
        .name = try allocator.dupe(u8, project_name),
    };

    try serialize(allocator);
}

fn executeListCommand(allocator: std.mem.Allocator) !void {
    try deserialize(allocator, .{});

    std.debug.print("{d} registered projects:\n", .{projects.len});
    for (projects) |project| {
        std.debug.print("{s}: {s}\n", .{ project.id, project.name });
    }
}

fn executeStartCommand(allocator: std.mem.Allocator, args_it: *std.process.ArgIterator) !void {
    const project_id = args_it.next() orelse {
        std.debug.print("Usage: " ++ exe_name ++ " start <project_id>\n", .{});
        return;
    };

    try deserialize(allocator, .{ .extra_entry = true });

    var project = findProject(project_id) orelse {
        std.debug.print("Project with given ID not found: {s}\n", .{project_id});
        std.debug.print("Known IDs:", .{});
        for (projects) |project| {
            std.debug.print(" {s}", .{project.id});
        }
        std.debug.print("\n", .{});
        return;
    };

    var entry = &entries[entries.len - 1];

    var raw_start = std.time.timestamp();
    var raw_end = std.time.timestamp();
    entry.* = Entry{
        .project_id = project.id,
        .start = Timestamp.now(),
        .end = Timestamp.now(),
    };

    while (true) {
        const raw_now = std.time.timestamp();
        const elapsed = raw_now - raw_start;
        const seconds = getSeconds(elapsed);
        const minutes = getMinutes(elapsed);
        const hours = getHours(elapsed);
        std.debug.print("{s}: {d}:{d:0>2}:{d:0>2}          \r", .{ project.name, hours, minutes, seconds });

        const entry_minutes = getMinutes(raw_end - raw_start);
        if (entry_minutes != minutes) {
            raw_end = raw_now;
            entry.end = Timestamp.now();
            try serialize(allocator);
        }

        const one_second = 1_000_000_000;
        std.time.sleep(one_second);
    }
}

fn serialize(allocator: std.mem.Allocator) !void {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();

    try text.writer().print("version: 1\n", .{});

    try text.writer().print("\n", .{});
    for (projects) |project| {
        try text.writer().print("project: {s} '{s}'\n", .{ project.id, project.name });
    }

    try text.writer().print("\n", .{});
    for (entries) |entry| {
        try text.writer().print("entry: {s} {s}..{s}\n", .{ entry.project_id, entry.start.toString(), entry.end.toString() });
    }

    try std.fs.cwd().writeFile(exe_name ++ "_session.ini", text.items);
}

fn deserialize(allocator: std.mem.Allocator, options: struct { extra_project: bool = false, extra_entry: bool = false }) !void {
    const text = std.fs.cwd().readFileAlloc(allocator, exe_name ++ "_session.ini", 1024 * 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer allocator.free(text);

    var projects_list = std.ArrayList(Project).init(allocator);
    defer projects_list.deinit();
    var entries_list = std.ArrayList(Entry).init(allocator);
    defer entries_list.deinit();

    var lines_it = std.mem.split(u8, text, "\n");
    const version_line = lines_it.next().?;
    const version = getTrimmedValue(version_line, "version");
    if (version == null or !std.mem.eql(u8, version.?, "1")) return error.UnsupportedVersion;

    while (lines_it.next()) |line| {
        if (getTrimmedValue(line, "project")) |project_str| {
            var space_split = std.mem.split(u8, project_str, " ");
            const id = space_split.next().?;
            const rest = project_str[id.len + 1 ..];
            const name = std.mem.trim(u8, rest, "'");
            try projects_list.append(.{
                .id = try allocator.dupe(u8, id),
                .name = try allocator.dupe(u8, name),
            });
        } else if (getTrimmedValue(line, "entry")) |entry_str| {
            var space_split = std.mem.split(u8, entry_str, " ");
            const project_id = space_split.next().?;
            const rest = entry_str[project_id.len + 1 ..];
            var range_it = std.mem.split(u8, rest, "..");
            const start_str = range_it.next().?;
            const end_str = range_it.next().?;
            try entries_list.append(.{
                .project_id = try allocator.dupe(u8, project_id),
                .start = try Timestamp.fromString(start_str),
                .end = try Timestamp.fromString(end_str),
            });
        }
    }

    if (options.extra_project) {
        try projects_list.append(undefined);
    }
    if (options.extra_entry) {
        try entries_list.append(undefined);
    }

    projects = try allocator.dupe(Project, projects_list.items);
    entries = try allocator.dupe(Entry, entries_list.items);
}

fn getTrimmedValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
    const prefix = name ++ ": ";
    if (std.mem.startsWith(u8, line, prefix)) {
        const raw = line[prefix.len..];
        return std.mem.trim(u8, raw, "\n\r\t ");
    }
    return null;
}

fn getSeconds(total_seconds: i64) u64 {
    return @intCast(@mod(total_seconds, 60));
}

fn getMinutes(total_seconds: i64) u64 {
    return @intCast(@mod(@divFloor(total_seconds, 60), 60));
}

fn getHours(total_seconds: i64) u64 {
    return @intCast(@divFloor(total_seconds, 60 * 60));
}

fn findProject(id: []const u8) ?*Project {
    for (projects) |*project| {
        if (std.mem.eql(u8, id, project.id)) {
            return project;
        }
    }
    return null;
}

const Project = struct {
    id: []const u8,
    name: []const u8,

    fn deinit(project: Project, allocator: std.mem.Allocator) void {
        allocator.free(project.id);
        allocator.free(project.name);
    }
};

const Entry = struct {
    project_id: []const u8,
    start: Timestamp,
    end: Timestamp,

    fn getHours(entry: Entry) f64 {
        const start = entry.start;
        const end = entry.end;
        std.debug.assert(start.year == end.year);
        std.debug.assert(start.month == end.month);
        std.debug.assert(start.day == end.day);
        const hour_diff = float(end.hour) - float(start.hour);
        const minute_diff = float(end.minute) - float(start.minute);
        const second_diff = float(end.second) - float(start.second);
        return hour_diff + minute_diff / 60.0 + second_diff / 60.0 / 60.0;
    }

    fn deinit(entry: Entry, allocator: std.mem.Allocator) void {
        allocator.free(entry.project_id);
    }
};

fn float(int: anytype) f64 {
    return @floatFromInt(int);
}

const Year = u16;
const Month = u4;
const Day = u5;
const Hour = u5;
const Minute = u6;
const Second = u6;

const Timestamp = struct {
    year: Year,
    month: Month,
    day: Day,
    hour: Hour,
    minute: Minute,
    second: Second,

    fn now() Timestamp {
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
    fn toString(t: Timestamp) [string_len]u8 {
        var buffer: [string_len]u8 = undefined;
        _ = std.fmt.bufPrint(&buffer, "{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}-{d:0>2}-{d:0>2}", .{ t.year, t.month, t.day, t.hour, t.minute, t.second }) catch unreachable;
        return buffer;
    }

    fn fromString(str: []const u8) !Timestamp {
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
};

const std = @import("std");
const zli = @import("zli");

const exe_name = "trecker";
const session_file_name = exe_name ++ "_session.ini";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args_it = try std.process.argsWithAllocator(allocator);
    defer args_it.deinit();

    const command = zli.parse(&args_it, Command);
    try switch (command) {
        .init => executeInitCommand(allocator),
        .start => |args| executeStartCommand(allocator, args.positional.project_id),
        .add => |args| executeAddCommand(
            allocator, args.positional.project_id, args.positional.project_name
        ),
        .list => executeListCommand(allocator),
        .summary => |args| executeSummaryCommand(
            allocator, args.positional.month, args.positional.year
        ),
    };
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}

fn executeInitCommand(allocator: std.mem.Allocator) !void {
    const file_exists = blk: {
        std.fs.cwd().access(session_file_name, .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk false;
            }
            return err;
        };
        break :blk true;
    };

    if (file_exists) {
        fatal(
            "Session file '{s}' already exists. Delete manually to create a new session.",
            .{ session_file_name }
        );
    }

    const store = Store{
        .projects = &.{},
        .entries = &.{},
    };
    try store.serialize(allocator);
}

fn executeSummaryCommand(allocator: std.mem.Allocator, month_str: []const u8, year_str: []const u8) !void {
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
        fatal("Unknown month: '{s}'", .{month_str});
    };

    const year = try std.fmt.parseInt(u16, year_str, 10);

    var project_hours = std.MultiArrayList(struct { p: *Project, h: f64 }){};
    defer project_hours.deinit(allocator);

    var store = try Store.deserialize(allocator, .{});
    defer store.deinit(allocator);
    for (store.projects) |*project| {
        try project_hours.append(allocator, .{ .p = project, .h = 0 });
    }

    var total_hours: f64 = 0;
    var work_days: [31]Day = undefined;
    var work_days_len: usize = 0;

    for (store.entries) |entry| {
        if (entry.start.month != month) continue;
        if (entry.start.year != year) continue;

        if (std.mem.indexOfScalar(Day, work_days[0..work_days_len], entry.start.day) == null) {
            work_days[work_days_len] = entry.start.day;
            work_days_len += 1;
        }

        const project_index = for (store.projects, 0..) |project, i| {
            if (std.mem.eql(u8, project.id, entry.project_id)) break i;
        } else unreachable;

        const hours = entry.getTotalHours();
        project_hours.items(.h)[project_index] += hours;
        total_hours += hours;
    }

    const avg_hours_per_day = total_hours / float(work_days_len);

    project_hours.sort(struct {
        hours: []const f64,
        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.hours[a] > ctx.hours[b];
        }
    }{ .hours = project_hours.items(.h) });

    std.debug.print("Total: {d:.2} hours ({d:.2} hours per day)\n", .{ total_hours, avg_hours_per_day });
    for (project_hours.items(.p), project_hours.items(.h)) |project, hours| {
        std.debug.print("{s}: {d:.2} hours ({d:.0} %)\n", .{ project.name, hours, 100.0 * hours / total_hours });
    }
}

fn executeAddCommand(allocator: std.mem.Allocator, project_id: []const u8, project_name: []const u8) !void {
    var store = try Store.deserialize(allocator, .{ .extra_project = true });
    defer store.deinit(allocator);
    store.projects[store.projects.len - 1] = .{
        .id = try allocator.dupe(u8, project_id),
        .name = try allocator.dupe(u8, project_name),
    };
    try store.serialize(allocator);
}

fn executeListCommand(allocator: std.mem.Allocator) !void {
    var store = try Store.deserialize(allocator, .{});
    defer store.deinit(allocator);
    std.debug.print("{d} registered projects:\n", .{store.projects.len});
    for (store.projects) |project| {
        std.debug.print("{s}: {s}\n", .{ project.id, project.name });
    }
}

fn executeStartCommand(allocator: std.mem.Allocator, project_id: []const u8) !void {
    var store = try Store.deserialize(allocator, .{ .extra_entry = true });
    defer store.deinit(allocator);

    const project = store.findProject(project_id) orelse {
        var message = std.ArrayList(u8).init(allocator);
        try message.writer().print("Project with given ID not found: {s}\n", .{project_id});
        try message.writer().print("Known IDs:", .{});
        for (store.projects) |project| {
            try message.writer().print(" {s}", .{project.id});
        }
        fatal("{s}", .{message.items});
    };

    var last_entry = &store.entries[store.entries.len - 1];

    const raw_start = std.time.timestamp();
    var raw_end = std.time.timestamp();
    last_entry.* = Entry{
        .project_id = project.id,
        .start = Timestamp.now(),
        .end = Timestamp.now(),
    };

    var initial_total_today: i64 = 0;
    for (store.entries) |other| {
        if (last_entry.start.year != other.start.year) continue;
        if (last_entry.start.month != other.start.month) continue;
        if (last_entry.start.day != other.start.day) continue;
        initial_total_today += other.getTotalSeconds();
    }

    while (true) {
        const raw_now = std.time.timestamp();
        const elapsed = raw_now - raw_start;
        const hours = getHours(elapsed);
        const minutes = getMinutes(elapsed);
        const seconds = getSeconds(elapsed);
        const total_today = elapsed + initial_total_today;
        std.debug.print("\r{s}: {d}:{d:0>2}:{d:0>2} (Today: {d}:{d:0>2}:{d:0>2})          \r", .{ project.name, hours, minutes, seconds, getHours(total_today), getMinutes(total_today), getSeconds(total_today) });

        const entry_minutes = getMinutes(raw_end - raw_start);
        if (entry_minutes != minutes) {
            raw_end = raw_now;
            last_entry.end = Timestamp.now();
            try store.serialize(allocator);
        }

        const one_second = 1_000_000_000;
        std.time.sleep(one_second);
    }
}

const Store = struct {
    projects: []Project,
    entries: []Entry,
    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        for (self.projects) |project| {
            project.deinit(allocator);
        }
        allocator.free(self.projects);
        for (self.entries) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(self.entries);
        self.* = undefined;
    }

    const DeserializeOptions = struct {
        extra_project: bool = false,
        extra_entry: bool = false,
    };
    fn deserialize(allocator: std.mem.Allocator, options: DeserializeOptions) !Store {
        const text = std.fs.cwd().readFileAlloc(
            allocator, session_file_name, 1024 * 1024 * 1024
        ) catch |err| switch (err) {
            error.FileNotFound => fatal(
                "Session file {s} was not found in the working directory. Run 'trecker init' to create a fresh one.",
                .{session_file_name},
            ),
            else => |e| return e,
        };
        defer allocator.free(text);
        return parse(allocator, options, text) catch |err| fatal(
            "{s}: parse error: {s}", .{session_file_name, @errorName(err)},
        );
    }

    fn parse(allocator: std.mem.Allocator, options: DeserializeOptions, text: []const u8) !Store {
        var projects: std.ArrayListUnmanaged(Project) = .{};
        defer projects.deinit(allocator);
        var entries: std.ArrayListUnmanaged(Entry) = .{};
        defer entries.deinit(allocator);

        var lines_it = std.mem.split(u8, text, "\n");
        const version_line = lines_it.first();
        const version = getTrimmedValue(version_line, "version");
        if (version == null) return error.MissingVersion;
        if (!std.mem.eql(u8, version.?, "1")) return error.UnsupportedVersion;

        while (lines_it.next()) |line| {
            if (getTrimmedValue(line, "project")) |project_str| {
                var space_split = std.mem.split(u8, project_str, " ");
                const id = space_split.first();
                const rest = project_str[id.len + 1 ..];
                const name = std.mem.trim(u8, rest, "'");
                try projects.append(allocator, .{
                    .id = try allocator.dupe(u8, id),
                    .name = try allocator.dupe(u8, name),
                });
            } else if (getTrimmedValue(line, "entry")) |entry_str| {
                var space_split = std.mem.split(u8, entry_str, " ");
                const project_id = space_split.first();
                const rest = entry_str[project_id.len + 1 ..];
                var range_it = std.mem.split(u8, rest, "..");
                const start_str = range_it.next().?;
                const end_str = range_it.next().?;
                try entries.append(allocator, .{
                    .project_id = try allocator.dupe(u8, project_id),
                    .start = try Timestamp.fromString(start_str),
                    .end = try Timestamp.fromString(end_str),
                });
            }
        }

        if (options.extra_project) {
            try projects.append(allocator, undefined);
        }
        if (options.extra_entry) {
            try entries.append(allocator, undefined);
        }

        return .{
            .projects = try projects.toOwnedSlice(allocator),
            .entries = try entries.toOwnedSlice(allocator),
        };
    }

    fn findProject(self: Store, id: []const u8) ?*Project {
        for (self.projects) |*project| {
            if (std.mem.eql(u8, id, project.id)) {
                return project;
            }
        }
        return null;
    }

    fn serialize(self: Store, allocator: std.mem.Allocator) !void {
        var text = std.ArrayList(u8).init(allocator);
        defer text.deinit();

        try text.writer().print("version: 1\n", .{});

        try text.writer().print("\n", .{});
        for (self.projects) |project| {
            try text.writer().print("project: {s} '{s}'\n", .{ project.id, project.name });
        }

        try text.writer().print("\n", .{});
        for (self.entries) |entry| {
            try text.writer().print("entry: {s} {s}..{s}\n", .{ entry.project_id, entry.start.toString(), entry.end.toString() });
        }

        try std.fs.cwd().writeFile(.{ .sub_path = session_file_name, .data = text.items });
    }

};

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

    fn getTotalHours(entry: Entry) f64 {
        return float(getTotalSeconds(entry)) / 60.0 / 60.0;
    }

    fn getTotalSeconds(entry: Entry) i64 {
        const start = entry.start;
        const end = entry.end;
        std.debug.assert(start.year == end.year);
        std.debug.assert(start.month == end.month);
        std.debug.assert(start.day == end.day);
        var hour_diff: i64 = end.hour;
        hour_diff -= start.hour;
        var minute_diff: i64 = end.minute;
        minute_diff -= start.minute;
        var second_diff: i64 = end.second;
        second_diff -= start.second;
        return hour_diff * 60 * 60 + minute_diff * 60 + second_diff;
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

const Command = union(enum) {
    pub const help =
        \\Usage trecker <command> [<argument>...]
        \\
        \\Commands:
        \\  init          Creates a fresh session file in the working directory.
        \\  start         Starts the trecker.
        \\  add           Adds a new project.
        \\  list          Lists all known projects.
        \\  summary       Prints the work summary for one specific month.
        \\
        \\General options:
        \\  -h, --help    Prints usage info.
        \\
    ;

    init: struct {
        pub const help = "Usage: trecker init\n";
    },
    start: struct {
        pub const help = "Usage: trecker start <project_id>\n";

        positional: struct {
            project_id: []const u8,
        },
    },
    add: struct {
        pub const help = "Usage: trecker add <project_id> <project_name>\n";

        positional: struct {
            project_id: []const u8,
            project_name: []const u8,
        },
    },
    list: struct {
        pub const help = "Usage: trecker list\n";
    },
    summary: struct {
        pub const help = "Usage: trecker summary <month> <year>\n";

        positional: struct {
            month: []const u8,
            year: []const u8,
        },
    },
};

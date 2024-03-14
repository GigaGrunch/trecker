const std = @import("std");

var gpa: std.mem.Allocator = undefined;
var arena: std.mem.Allocator = undefined;

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    gpa = gpa_impl.allocator();
    defer _ = gpa_impl.deinit();
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    arena = arena_impl.allocator();
    defer arena_impl.deinit();

    try deserialize();

    var args_it = try std.process.argsWithAllocator(arena);
    _ = args_it.next().?; // first arg is the exe's name
    const command = args_it.next() orelse {
        std.debug.print("Usage: ztracker <command> [args...]\n", .{});
        return;
    };

    if (std.mem.eql(u8, command, "start")) {
        try executeStartCommand(&args_it);
    } else if (std.mem.eql(u8, command, "add")) {
        try executeAddCommand(&args_it);
    } else if (std.mem.eql(u8, command, "list")) {
        try executeListCommand(&args_it);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
    }
}

fn executeAddCommand(args_it: *std.process.ArgIterator) !void {
    const usage = "Usage: ztracker add <project_it> <project_name>\n";
    const project_id = args_it.next() orelse {
        std.debug.print(usage, .{});
        return;
    };
    const project_name = args_it.next() orelse {
        std.debug.print(usage, .{});
        return;
    };

    projects = try arena.realloc(projects, projects.len + 1);
    projects[projects.len - 1] = .{
        .id = try arena.dupe(u8, project_id),
        .name = try arena.dupe(u8, project_name),
        .entries = &.{},
    };

    try serialize();
}

fn executeListCommand(args_it: *std.process.ArgIterator) !void {
    _ = args_it;
    std.debug.print("{d} registered projects:\n", .{projects.len});
    for (projects) |project| {
        std.debug.print("{s}: {s}\n", .{project.id, project.name});
    }
}

fn executeStartCommand(args_it: *std.process.ArgIterator) !void {
    const project_id = args_it.next() orelse {
        std.debug.print("Usage: ztracker start <project_id>\n", .{});
        return;
    };
    var project = findProject(project_id) orelse {
        std.debug.print("Project with given ID not found: {s}\n", .{project_id});
        std.debug.print("Known IDs:", .{});
        for (projects) |project| {
            std.debug.print(" {s}", .{project.id});
        }
        std.debug.print("\n", .{});
        return;
    };

    project.entries = try arena.realloc(project.entries, project.entries.len + 1);
    var entry = &project.entries[project.entries.len - 1];

    var raw_start = std.time.timestamp();
    var raw_end = std.time.timestamp();
    entry.* = Entry {
        .start = Timestamp.now(),
        .end = Timestamp.now(),
    };

    while (true) {
        const raw_now = std.time.timestamp();
        const elapsed = raw_now - raw_start;
        const seconds: u8 = @intCast(@mod(elapsed, 60));
        const minutes = getMinutes(elapsed);
        std.debug.print("{s}: {d}:{d:0>2}          \r", .{project.name, minutes, seconds});

        const entry_minutes = getMinutes(raw_end - raw_start);
        if (entry_minutes != minutes) {
            raw_end = raw_now;
            entry.end = Timestamp.now();
            try serialize();
        }

        const one_second = 1_000_000_000;
        std.time.sleep(one_second);
    }
}

fn serialize() !void {
    var text = std.ArrayList(u8).init(gpa);
    defer text.deinit();

    try text.writer().print("version: 1\n\n", .{});

    for (projects) |project| {
        try text.writer().print("id: {s}\n", .{project.id});
        try text.writer().print("name: {s}\n", .{project.name});
        try text.writer().print("entries_len: {d}\n", .{project.entries.len});
        for (project.entries) |entry| {
            try text.writer().print("entry: {s}..{s}\n", .{entry.start.toString(), entry.end.toString()});
        }
        try text.writer().print("\n", .{});
    }

    try std.fs.cwd().writeFile("ztracker_session.ini", text.items);
}

fn deserialize() !void {
    const text = std.fs.cwd().readFileAlloc(gpa, "ztracker_session.ini", 1024 * 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer gpa.free(text);

    var projects_list = std.ArrayList(Project).init(arena);

    var block_it = std.mem.split(u8, text, "\n\n");
    const version_block = block_it.next().?;
    if (!std.mem.startsWith(u8, version_block, "version: 1")) return error.UnsupportedVersion;

    while (block_it.next()) |project_block| {
        if (std.mem.trim(u8, project_block, "\n\r\t ").len == 0) continue;

        var project_id: []const u8 = undefined;
        var project_name: []const u8 = undefined;
        var entries: []Entry = undefined;

        var parsed_entries: usize = 0;
        var line_it = std.mem.split(u8, project_block, "\n");
        while (line_it.next()) |line| {
            if (getTrimmedValue(line, "id")) |id| {
                project_id = try arena.dupe(u8, id);
            } else if (getTrimmedValue(line, "name")) |name| {
                project_name = try arena.dupe(u8, name);
            } else if (getTrimmedValue(line, "entries_len")) |len_str| {
                const entries_len = try std.fmt.parseInt(usize, len_str, 10);
                entries = try arena.alloc(Entry, entries_len);
            } else if (getTrimmedValue(line, "entry")) |entry_str| {
                var part_it = std.mem.split(u8, entry_str, "..");
                const start_str = part_it.next().?;
                const end_str = part_it.next().?;
                entries[parsed_entries] = .{
                    .start = try Timestamp.fromString(start_str),
                    .end = try Timestamp.fromString(end_str),
                };
                parsed_entries += 1;
            }
        }

        std.debug.assert(entries.len == parsed_entries);

        try projects_list.append(.{
            .id = project_id,
            .name = project_name,
            .entries = entries,
        });
    }

    projects = projects_list.items;
}

fn getRawValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
    const prefix = name ++ ": ";
    if (std.mem.startsWith(u8, line, prefix)) {
        return line[prefix.len..];
    }
    return null;
}

fn getTrimmedValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
    if (getRawValue(line, name)) |raw_value| {
        return std.mem.trim(u8, raw_value, "\n\r\t ");
    }
    return null;
}

fn getMinutes(seconds: i64) u64 {
    return @intCast(@divFloor(seconds, 60));
}

fn findProject(id: []const u8) ?*Project {
    for (projects) |*project| {
        if (std.mem.eql(u8, id, project.id)) {
            return project;
        }
    }
    return null;
}

var projects: []Project = undefined;

const Project = struct {
    id: []const u8,
    name: []const u8,
    entries: []Entry,
};

const Entry = struct {
    start: Timestamp,
    end: Timestamp,
};

const Timestamp = struct {
    year: u16,
    month: u4,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,

    fn now() Timestamp {
        const epoch_seconds = std.time.timestamp();
        return fromEpochSeconds(@intCast(epoch_seconds));
    }

    fn fromEpochSeconds(seconds: u64) Timestamp {
        const epoch_seconds = std.time.epoch.EpochSeconds { .secs = seconds };
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
        _ = std.fmt.bufPrint(&buffer, "{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}-{d:0>2}-{d:0>2}", .{
            t.year, t.month, t.day, t.hour, t.minute, t.second
        }) catch unreachable;
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

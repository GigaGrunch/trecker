const std = @import("std");
const util = @import("util.zig");
const Store = @import("Store.zig");
const Timestamp = @import("Timestamp.zig");

pub fn version() !void {
    const build_info = @import("build_info");
    std.debug.print("Git commit hash: {s}\n", .{build_info.git_commit_hash});
    std.debug.print("Built with Zig {d}.{d}.{d}\n", .{ build_info.zig_version.major, build_info.zig_version.minor, build_info.zig_version.patch });
}

pub fn init(allocator: std.mem.Allocator) !void {
    const file_exists = blk: {
        std.fs.cwd().access(util.session_file_name, .{}) catch |err| {
            if (err == error.FileNotFound) {
                break :blk false;
            }
            return err;
        };
        break :blk true;
    };

    if (file_exists) {
        util.fatal("Session file '{s}' already exists. Delete manually to create a new session.", .{util.session_file_name});
    }

    const store = Store{
        .projects = &.{},
        .entries = &.{},
    };
    try store.serialize(allocator);
}

const Summary = struct {
    project_hours: std.MultiArrayList(struct { p: *Store.Project, h: f64 }) = .{},
    total_hours: f64 = 0,
    avg_hours_per_day: f64 = 0,
};

pub fn csv_summary(allocator: std.mem.Allocator, month_str: []const u8, year_str: []const u8, user_name: []const u8) !void {
    var summary = Summary{};
    defer summary.project_hours.deinit(allocator);

    var store = try Store.deserialize(allocator, .{});
    defer store.deinit(allocator);

    try collect_hours(allocator, month_str, year_str, &store, &summary);

    for (summary.project_hours.items(.p), summary.project_hours.items(.h)) |project, hours| {
        if (hours > 0) {
            std.debug.print("{s},{s},{d:.0}%\n", .{ user_name, project.name, 100.0 * hours / summary.total_hours });
        }
    }
}

pub fn text_summary(allocator: std.mem.Allocator, month_str: []const u8, year_str: []const u8) !void {
    var summary = Summary{};
    defer summary.project_hours.deinit(allocator);

    var store = try Store.deserialize(allocator, .{});
    defer store.deinit(allocator);

    try collect_hours(allocator, month_str, year_str, &store, &summary);

    std.debug.print("Total: {d:.2} hours ({d:.2} hours per day)\n", .{ summary.total_hours, summary.avg_hours_per_day });
    for (summary.project_hours.items(.p), summary.project_hours.items(.h)) |project, hours| {
        if (hours > 0) {
            std.debug.print("{s}: {d:.2} hours ({d:.0} %)\n", .{ project.name, hours, 100.0 * hours / summary.total_hours });
        }
    }
}

fn collect_hours(allocator: std.mem.Allocator, month_str: []const u8, year_str: []const u8, store: *Store, summary: *Summary) !void {
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
    const month: Timestamp.Month = for (month_names, 1..) |month_name, number| {
        if (std.mem.eql(u8, month_str, month_name)) {
            break @enumFromInt(number);
        }
    } else {
        util.fatal("Unknown month: '{s}'", .{month_str});
    };

    const year = try std.fmt.parseInt(u16, year_str, 10);

    for (store.projects) |*project| {
        try summary.project_hours.append(allocator, .{ .p = project, .h = 0 });
    }

    var work_days: [31]Timestamp.Day = undefined;
    var work_days_len: usize = 0;

    for (store.entries) |entry| {
        if (entry.start.time.month != month) continue;
        if (entry.start.time.year != year) continue;

        if (std.mem.indexOfScalar(Timestamp.Day, work_days[0..work_days_len], entry.start.time.day) == null) {
            work_days[work_days_len] = entry.start.time.day;
            work_days_len += 1;
        }

        const project_index = for (store.projects, 0..) |project, i| {
            if (std.mem.eql(u8, project.id, entry.project_id)) break i;
        } else unreachable;

        const hours = entry.getTotalHours();
        summary.project_hours.items(.h)[project_index] += hours;
        summary.total_hours += hours;
    }

    summary.avg_hours_per_day = summary.total_hours / util.float(work_days_len);

    summary.project_hours.sort(struct {
        hours: []const f64,
        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            return ctx.hours[a] > ctx.hours[b];
        }
    }{ .hours = summary.project_hours.items(.h) });
}

pub fn add(allocator: std.mem.Allocator, project_id: []const u8, project_name: []const u8) !void {
    var store = try Store.deserialize(allocator, .{ .extra_project = true });
    defer store.deinit(allocator);
    store.projects[store.projects.len - 1] = .{
        .id = try allocator.dupe(u8, project_id),
        .name = try allocator.dupe(u8, project_name),
    };
    try store.serialize(allocator);
}

pub fn list(allocator: std.mem.Allocator) !void {
    var store = try Store.deserialize(allocator, .{});
    defer store.deinit(allocator);
    std.debug.print("{d} registered projects:\n", .{store.projects.len});
    for (store.projects) |project| {
        std.debug.print("{s}: {s}\n", .{ project.id, project.name });
    }
}

pub fn start(allocator: std.mem.Allocator, project_id: []const u8) !void {
    var store = try Store.deserialize(allocator, .{ .extra_entry = true });
    defer store.deinit(allocator);

    const project = store.findProject(project_id) orelse {
        var message = std.ArrayList(u8).init(allocator);
        try message.writer().print("Project with given ID not found: {s}\n", .{project_id});
        try message.writer().print("Known IDs:", .{});
        for (store.projects) |project| {
            try message.writer().print(" {s}", .{project.id});
        }
        util.fatal("{s}", .{message.items});
    };

    var last_entry = &store.entries[store.entries.len - 1];

    const raw_start = std.time.timestamp();
    var raw_end = std.time.timestamp();
    last_entry.* = Store.Entry{
        .project_id = project.id,
        .start = try Timestamp.now(allocator),
        .end = try Timestamp.now(allocator),
    };

    var initial_total_today: i64 = 0;
    for (store.entries) |other| {
        if (last_entry.start.time.year != other.start.time.year) continue;
        if (last_entry.start.time.month != other.start.time.month) continue;
        if (last_entry.start.time.day != other.start.time.day) continue;
        initial_total_today += other.getTotalSeconds();
    }

    const redraw_lines = 2;
    std.debug.print("--- Trecker --- \n", .{});
    std.debug.print("Project: {s} ({s})\n", .{ project.name, project.id });
    for (1..redraw_lines) |_| {
        std.debug.print("\n", .{});
    }

    while (true) {
        const raw_now = std.time.timestamp();
        const elapsed = raw_now - raw_start;
        const hours = getHours(elapsed);
        const minutes = getMinutes(elapsed);
        const seconds = getSeconds(elapsed);
        const total_today = elapsed + initial_total_today;
        const total_hours = getHours(total_today);
        const total_minutes = getMinutes(total_today);
        const total_seconds = getSeconds(total_today);

        const go_to_first_line = std.fmt.comptimePrint("\x1b[{d}A", .{redraw_lines - 1});
        const clear_line = "\x1b[2K\r";
        std.debug.print("{s}", .{go_to_first_line});
        std.debug.print("{s}", .{clear_line});
        std.debug.print("Current entry: {d}:{d:0>2}:{d:0>2}\n", .{ hours, minutes, seconds });
        std.debug.print("{s}", .{clear_line});
        std.debug.print("Total today: {d}:{d:0>2}:{d:0>2}", .{ total_hours, total_minutes, total_seconds });

        std.debug.print("\x1b]0;{s} {s} {d}:{d:0>2}:{d:0>2}\x07", .{ util.exe_name, project.id, total_hours, total_minutes, total_seconds });

        const entry_minutes = getMinutes(raw_end - raw_start);
        if (entry_minutes != minutes) {
            raw_end = raw_now;
            last_entry.end = try Timestamp.now(allocator);
            try store.serialize(allocator);
        }

        const one_second = 1_000_000_000;
        std.time.sleep(one_second);
    }
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

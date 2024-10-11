const std = @import("std");
const util = @import("util.zig");
const Timestamp = @import("Timestamp.zig");
const Store = @This();

const file_format_version = 2;
const file_format_version_str = std.fmt.comptimePrint("{d}", .{file_format_version});

projects: []Project,
entries: []Entry,

const DeserializeOptions = struct { extra_project: bool = false, extra_entry: bool = false };
pub fn deserialize(allocator: std.mem.Allocator, options: DeserializeOptions) !Store {
    const text = std.fs.cwd().readFileAlloc(allocator, util.session_file_name, 1024 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => util.fatal(
            "Session file {s} was not found in the working directory. Run 'trecker init' to create a fresh one.",
            .{util.session_file_name},
        ),
        else => |e| return e,
    };
    defer allocator.free(text);
    return parse(allocator, options, text) catch |err| util.fatal(
        "{s}: parse error: {s}",
        .{ util.session_file_name, @errorName(err) },
    );
}

pub fn serialize(self: Store, allocator: std.mem.Allocator) !void {
    var text = std.ArrayList(u8).init(allocator);
    defer text.deinit();

    try text.writer().print("version: {d}\n", .{file_format_version});

    try text.writer().print("\n", .{});
    for (self.projects) |project| {
        try text.writer().print("project: {s} '{s}'\n", .{ project.id, project.name });
    }

    try text.writer().print("\n", .{});
    for (self.entries) |entry| {
        const start_str = try entry.start.toString();
        const end_str = try entry.end.toString();
        try text.writer().print("entry: {s} {s}..{s}\n", .{ entry.project_id, start_str, end_str });
    }

    try std.fs.cwd().writeFile(.{ .sub_path = util.session_file_name, .data = text.items });
}

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

pub fn findProject(self: Store, id: []const u8) ?*Project {
    for (self.projects) |*project| {
        if (std.mem.eql(u8, id, project.id)) {
            return project;
        }
    }
    return null;
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
    if (!std.mem.eql(u8, version.?, file_format_version_str)) return error.UnsupportedVersion;

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

fn getTrimmedValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
    const prefix = name ++ ": ";
    if (std.mem.startsWith(u8, line, prefix)) {
        const raw = line[prefix.len..];
        return std.mem.trim(u8, raw, "\n\r\t ");
    }
    return null;
}

pub const Project = struct {
    id: []const u8,
    name: []const u8,

    fn deinit(project: Project, allocator: std.mem.Allocator) void {
        allocator.free(project.id);
        allocator.free(project.name);
    }
};

pub const Entry = struct {
    project_id: []const u8,
    start: Timestamp,
    end: Timestamp,

    pub fn getTotalHours(entry: Entry) f64 {
        return util.float(getTotalSeconds(entry)) / 60.0 / 60.0;
    }

    pub fn getTotalSeconds(entry: Entry) i64 {
        const start = entry.start.time;
        const end = entry.end.time;
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

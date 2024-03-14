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
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
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

    var entries = try arena.alloc(Entry, project.entries.len + 1);
    @memcpy(entries[0..project.entries.len], project.entries);

    var entry = &entries[project.entries.len];
    project.entries = entries;

    entry.* = Entry {
        .start = std.time.timestamp(),
        .end = std.time.timestamp(),
    };

    try serialize();

    while (true) {
        const now = std.time.timestamp();
        const elapsed = now - entry.start;
        const seconds: u8 = @intCast(@mod(elapsed, 60));
        const minutes = getMinutes(elapsed);
        std.debug.print("{s}: {d}:{d:0>2}\r", .{project.name, minutes, seconds});

        const entry_minutes = getMinutes(entry.end - entry.start);
        if (entry_minutes != minutes) {
            entry.end = now;
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
        try text.writer().print("entries: ", .{});
        for (project.entries) |entry| {
            try text.appendSlice(&std.mem.toBytes(entry));
        }
        try text.writer().print("\n", .{});
    }

    try std.fs.cwd().writeFile("ztracker_session.ini", text.items);
}

fn deserialize() !void {
    const text = try std.fs.cwd().readFileAlloc(gpa, "ztracker_session.ini", 1024 * 1024 * 1024);
    defer gpa.free(text);

    var projects_list = std.ArrayList(Project).init(arena);

    var block_it = std.mem.split(u8, text, "\n\n");
    const version_block = block_it.next().?;
    if (!std.mem.startsWith(u8, version_block, "version: 1")) return error.UnsupportedVersion;

    while (block_it.next()) |project_block| {
        var project: Project = undefined;

        var line_it = std.mem.split(u8, project_block, "\n");
        while (line_it.next()) |line| {
            if (getTrimmedValue(line, "id")) |id| {
                var id_copy = try arena.alloc(u8, id.len);
                @memcpy(id_copy, id);
                project.id = id_copy;
            } else if (getTrimmedValue(line, "name")) |name| {
                var name_copy = try arena.alloc(u8, name.len);
                @memcpy(name_copy, name);
                project.name = name_copy;
            } else if (getTrimmedValue(line, "entries_len")) |len_str| {
                const entries_len = try std.fmt.parseInt(usize, len_str, 10);
                project.entries = try arena.alloc(Entry, entries_len);
            } else if (getRawValue(line, "entries")) |entries_raw| {
                for (project.entries, 0..) |*entry, i| {
                    const entry_start = i * @sizeOf(Entry);
                    const entry_end = entry_start + @sizeOf(Entry);
                    var array: [@sizeOf(Entry)]u8 = undefined;
                    @memcpy(&array, entries_raw[entry_start..entry_end]);
                    entry.* = std.mem.bytesToValue(Entry, &array);
                }
            }
        }

        try projects_list.append(project);
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
    start: i64,
    end: i64,
};

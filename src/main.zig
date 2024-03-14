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
    std.debug.print("serialize!\n", .{});
}

fn getMinutes(seconds: i64) u64 {
    return @intCast(@divFloor(seconds, 60));
}

fn findProject(id: []const u8) ?*Project {
    for (&projects) |*project| {
        if (std.mem.eql(u8, id, project.id)) {
            return project;
        }
    }
    return null;
}

var projects = [_]Project {
    .{
        .id = "rnd",
        .name = "R&D",
        .entries = &.{},
    },
};

const Project = struct {
    id: []const u8,
    name: []const u8,
    entries: []Entry,
};

const Entry = struct {
    start: i64,
    end: i64,
};

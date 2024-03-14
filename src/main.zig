const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var args_it = try std.process.argsWithAllocator(arena.allocator());
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

    const start_time = std.time.timestamp();
    while (true) {
        const elapsed = std.time.timestamp() - start_time;
        const seconds: u8 = @intCast(@mod(elapsed, 60));
        const minutes: u8 = @intCast(@divFloor(elapsed, 60));
        std.debug.print("{s}: {d}:{d:0>2}\r", .{project.name, minutes, seconds});

        const one_second = 1_000_000_000;
        std.time.sleep(one_second);
    }
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
    .{ .id = "rnd", .name = "R&D" },
};

const Project = struct {
    id: []const u8,
    name: []const u8,
};

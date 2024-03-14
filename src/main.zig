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

    std.debug.print("project name: {s}\n", .{project.name});
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

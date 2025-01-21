const std = @import("std");
const util = @import("util.zig");
const Args = @This();

pub const name = util.exe_name;

pub fn parseOrExit(args_it: *std.process.ArgIterator) Args {
    _ = args_it.skip();
    const command_name = args_it.next() orelse util.fatal("TODO", .{});
    const command_enum = std.meta.stringToEnum(std.meta.FieldEnum(Command), command_name) orelse util.fatal("TODO", .{});

    return .{ .command = switch (command_enum) {
        .init => .{ .init = .{} },
        .start => .{ .start = .{
            .positional = .{ .project_id = args_it.next() orelse util.fatal("TODO", .{}) },
        }},
        .add => .{ .add = .{
            .positional = .{
                .project_id = args_it.next() orelse util.fatal("TODO", .{}),
                .project_name = args_it.next() orelse util.fatal("TODO", .{}),
            },
        }},
        .list => .{ .list = .{} },
        .summary => .{ .summary = .{
            .positional = .{
                .month = args_it.next() orelse util.fatal("TODO", .{}),
                .year = args_it.next() orelse util.fatal("TODO", .{}),
            },
        }},
        .csv => .{ .csv = .{
            .positional = .{
                .month = args_it.next() orelse util.fatal("TODO", .{}),
                .year = args_it.next() orelse util.fatal("TODO", .{}),
                .user_name = args_it.next() orelse util.fatal("TODO", .{}),
            },
        }},
        .version => .{ .version = .{} },
    }};
}

command: Command,

const Command = union(enum) {
    pub const descriptions = .{
        .init = "Creates a fresh session file in the working directory.",
        .start = "Starts the trecker.",
        .add = "Adds a new project.",
        .list = "Lists all known projects.",
        .summary = "Prints the work summary for one specific month.",
        .csv = "Prints the work summary for one specific month in csv format.",
        .version = "Prints info about the version of " ++ name,
    };

    init: struct {},
    start: struct {
        positional: struct {
            project_id: []const u8,
        },
    },
    add: struct {
        positional: struct {
            project_id: []const u8,
            project_name: []const u8,
        },
    },
    list: struct {},
    summary: struct {
        positional: struct {
            month: []const u8,
            year: []const u8,
        },
    },
    csv: struct {
        positional: struct {
            month: []const u8,
            year: []const u8,
            user_name: []const u8,
        },
    },
    version: struct {},
};

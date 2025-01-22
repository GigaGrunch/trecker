const std = @import("std");
const util = @import("util.zig");
const Args = @This();

pub fn parseOrExit(args_it: *std.process.ArgIterator) Args {
    _ = args_it.skip();
    const command_name = args_it.next() orelse {
        util.fatal("Usage: {s} <command> [args...]\nCommands:\n{s}", .{util.exe_name, command_list});
    };
    const command_enum = std.meta.stringToEnum(std.meta.FieldEnum(Command), command_name) orelse {
        util.fatal("Unknown command: {s}\nKnown commands: {s}", .{
            command_name,
            command_names,
        });
    };

    return .{ .command = switch (command_enum) {
        .init => .{ .init = .{} },
        .start => .{ .start = .{
            .project_id = getPositionalArg(args_it, "project_id"),
        }},
        .add => .{ .add = .{
            .project_id = getPositionalArg(args_it, "project_id"),
            .project_name = getPositionalArg(args_it, "project_name"),
        }},
        .list => .{ .list = .{} },
        .summary => .{ .summary = .{
            .month = getPositionalArg(args_it, "month"),
            .year = getPositionalArg(args_it, "year"),
        }},
        .csv => .{ .csv = .{
            .month = getPositionalArg(args_it, "month"),
            .year = getPositionalArg(args_it, "year"),
            .user_name = getPositionalArg(args_it, "user_name"),
        }},
        .version => .{ .version = .{} },
    }};
}

fn getPositionalArg(args_it: *std.process.ArgIterator, name: []const u8) []const u8 {
    return args_it.next() orelse util.fatal("Missing positional argument: {s}", .{name});
}

const command_names = blk: {
    var result: []const u8 = "";
    for (std.meta.fields(Command)) |field| {
        if (result.len == 0) {
            result = field.name;
        } else {
            result = std.fmt.comptimePrint("{s}, {s}", .{result, field.name});
        }
    }
    break :blk result;
};

const command_list = command_list_blk: {
    const indent: []const u8 = "  ";
    var result: []const u8 = "";

    const max_len = max_len_blk: {
        var max_len_result = 0;
        for (std.meta.fields(Command)) |field| {
            max_len_result = @max(max_len_result, field.name.len);
        }
        break :max_len_blk max_len_result;
    };

    for (std.meta.fields(Command)) |field| {
        const name_format = std.fmt.comptimePrint("{{s:<{d}}}", .{max_len});
        const field_name = indent ++ std.fmt.comptimePrint(name_format, .{field.name});

        if (result.len == 0) {
            result = field_name;
        } else {
            result = result ++ "\n" ++ field_name;
        }

        for (std.meta.fields(field.type)) |arg| {
            result = result ++ std.fmt.comptimePrint(" <{s}>", .{arg.name});
        }
    }
    break :command_list_blk result;
};

command: Command,

const Command = union(enum) {
    pub const descriptions = .{
        .init = "Creates a fresh session file in the working directory.",
        .start = "Starts the trecker.",
        .add = "Adds a new project.",
        .list = "Lists all known projects.",
        .summary = "Prints the work summary for one specific month.",
        .csv = "Prints the work summary for one specific month in csv format.",
        .version = "Prints info about the version of " ++ util.exe_name,
    };

    init: struct {},
    start: struct {
        project_id: []const u8,
    },
    add: struct {
        project_id: []const u8,
        project_name: []const u8,
    },
    list: struct {},
    summary: struct {
        month: []const u8,
        year: []const u8,
    },
    csv: struct {
        month: []const u8,
        year: []const u8,
        user_name: []const u8,
    },
    version: struct {},
};

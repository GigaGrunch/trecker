const std = @import("std");
const util = @import("util.zig");
const Args = @This();

pub fn parseOrExit(args_it: *std.process.ArgIterator) Args {
    const usage_message = std.fmt.comptimePrint("Usage: {s} <command> [args...]\nCommands:\n{s}", .{util.exe_name, command_list});

    _ = args_it.skip();
    const command_name = args_it.next() orelse {
        util.fatal(usage_message, .{});
    };
    const command_enum = std.meta.stringToEnum(std.meta.FieldEnum(Command), command_name) orelse {
        util.fatal("Unknown command: {s}\n{s}", .{
            command_name,
            usage_message,
        });
    };

    defer {
        const args_list = args_lists.get(command_name).?;
        if (args_it.skip()) util.fatal("Too many positional arguments.\nUsage: {s} {s}", .{command_name, args_list});
    }

    return .{ .command = switch (command_enum) {
        .init => .{ .init = .{} },
        .start => .{ .start = .{
            .project_id = getPositionalArg(command_enum, args_it, "project_id"),
        }},
        .add => .{ .add = .{
            .project_id = getPositionalArg(command_enum, args_it, "project_id"),
            .project_name = getPositionalArg(command_enum, args_it, "project_name"),
        }},
        .list => .{ .list = .{} },
        .summary => .{ .summary = .{
            .month = getPositionalArg(command_enum, args_it, "month"),
            .year = getPositionalArg(command_enum, args_it, "year"),
        }},
        .csv => .{ .csv = .{
            .month = getPositionalArg(command_enum, args_it, "month"),
            .year = getPositionalArg(command_enum, args_it, "year"),
            .user_name = getPositionalArg(command_enum, args_it, "user_name"),
        }},
        .version => .{ .version = .{} },
    }};
}

fn getPositionalArg(command: std.meta.FieldEnum(Command), args_it: *std.process.ArgIterator, name: []const u8) []const u8 {
    const command_name = @tagName(command);
    const args_list = args_lists.get(command_name).?;
    return args_it.next() orelse util.fatal("Missing positional argument: {s}\nUsage: {s} {s}", .{name, command_name, args_list});
}

const command_list = command_list_blk: {
    const indent: []const u8 = "  ";
    var result: []const u8 = "";

    const max_field_name_len = max_field_name_len_blk: {
        var max_field_name_len_result = 0;
        for (std.meta.fields(Command)) |field| {
            max_field_name_len_result = @max(max_field_name_len_result, field.name.len);
        }
        break :max_field_name_len_blk max_field_name_len_result;
    };

    const max_args_list_len = max_args_list_len_blk: {
        var max_args_list_len_result = 0;
        for (args_lists.values()) |value| {
            max_args_list_len_result = @max(max_args_list_len_result, value.len);
        }
        break :max_args_list_len_blk max_args_list_len_result;
    };

    for (std.meta.fields(Command)) |field| {
        const name_format = std.fmt.comptimePrint("{{s:<{d}}}", .{max_field_name_len});
        const field_name = indent ++ std.fmt.comptimePrint(name_format, .{field.name});

        if (result.len == 0) {
            result = field_name;
        } else {
            result = result ++ "\n" ++ field_name;
        }

        const args_list = args_lists.get(field.name).?;
        const args_list_format = std.fmt.comptimePrint(" {{s:<{d}}}", .{max_args_list_len});
        result = result ++ std.fmt.comptimePrint(args_list_format, .{args_list});

        const command_value = std.meta.stringToEnum(std.meta.FieldEnum(Command), field.name).?;
        result = result ++ " " ++ getDescription(command_value);
    }
    break :command_list_blk result;
};

const args_lists = args_lists_blk: {
    const fields = std.meta.fields(Command);
    var kvs: [fields.len] struct { []const u8, []const u8 } = undefined;
    for (fields, 0..) |field, field_i| {
        const key = &kvs[field_i][0];
        const value = &kvs[field_i][1];
        key.* = field.name;
        value.* = "";
        for (std.meta.fields(field.type), 0..) |arg, arg_i| {
            if (arg_i > 0) value.* = value.* ++ " ";
            value.* = value.* ++ std.fmt.comptimePrint("<{s}>", .{arg.name});
        }
    }
    break :args_lists_blk std.StaticStringMap([]const u8).initComptime(kvs);
};

fn getDescription(command: std.meta.FieldEnum(Command)) []const u8 {
    return switch (command) {
        .init => "Creates a fresh session file in the working directory.",
        .start => "Starts the trecker.",
        .add => "Adds a new project.",
        .list => "Lists all known projects.",
        .summary => "Prints the work summary for one specific month.",
        .csv => "Prints the work summary for one specific month in csv format.",
        .version => std.fmt.comptimePrint("Prints info about the version of {s}.", .{util.exe_name}),
    };
}

command: Command,

const Command = union(enum) {
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

pub const name = "trecker";

command: union(enum) {
    pub const descriptions = .{
        .init = "Creates a fresh session file in the working directory.",
        .start = "Starts the trecker.",
        .add = "Adds a new project.",
        .list = "Lists all known projects.",
        .summary = "Prints the work summary for one specific month.",
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
    version: struct {},
},

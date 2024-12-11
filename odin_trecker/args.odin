package trecker

import "core:strings"
import "core:fmt"

Args :: struct {
    type: enum {
        init,
        add,
        start,
    },
    
    inner: union {
        AddArgs,
        StartArgs,
    },
}

AddArgs :: struct {
    project_name: string,
    project_id: string,
}

StartArgs :: struct {
    project_id: string,
}

parse_args :: proc(raw_args: []string) -> (Args, bool) {
    if len(raw_args) < 1 {
        fmt.println("No args were passed.")
        return {}, false
    }

    command_str := raw_args[0]

    if strings.compare(command_str, "init") == 0 {
        return Args { type = .init }, true
    }
    if strings.compare(command_str, "add") == 0 {
        if len(raw_args) < 2 {
            fmt.println("Missing argument: project_id")
            return {}, false
        }
        if len(raw_args) < 3 {
            fmt.println("Missing argument: project_name")
            return {}, false
        }
        
        return Args {
            type = .add,
            inner = AddArgs {
                project_id = raw_args[1],
                project_name = raw_args[2],
            },
        }, true
    }
    if strings.compare(command_str, "start") == 0 {
        if len(raw_args) < 2 {
            fmt.println("Missing argument: project_id")
            return {}, false
        }
        
        return Args {
            type = .start,
            inner = StartArgs { project_id = raw_args[1] },
        }, true
    }

    fmt.printfln("Unknown command: '%v'.", command_str)
    return {}, false
}

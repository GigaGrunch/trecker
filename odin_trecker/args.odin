package trecker

import "core:strings"
import "core:fmt"

Args :: struct {
    type: enum {
        init,
        add,
        start,
        list,
        summary,
    },
    
    inner: union {
        Add_Args,
        Start_Args,
        Summary_Args,
    },
}

Add_Args :: struct {
    project_name: string,
    project_id: string,
}

Start_Args :: struct {
    project_id: string,
}

Summary_Args :: struct {
    month: string,
    year: string,
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
            inner = Add_Args {
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
            inner = Start_Args { project_id = raw_args[1] },
        }, true
    }
    if strings.compare(command_str, "list") == 0 {
        return Args { type = .list }, true
    }
    if strings.compare(command_str, "summary") == 0 {
        if len(raw_args) < 2 {
            fmt.println("Missing argument: month")
            return {}, false
        }
        if len(raw_args) < 3 {
            fmt.println("Missing argument: year")
            return {}, false
        }
        
        return Args {
            type = .summary,
            inner = Summary_Args {
                month = raw_args[1],
                year = raw_args[2],
            },
        }, true
    }

    fmt.printfln("Unknown command: '%v'.", command_str)
    return {}, false
}

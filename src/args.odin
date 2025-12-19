package trecker

import "core:strings"
import "core:fmt"
import "core:reflect"

Command :: enum {
    init,
    add,
    start,
    list,
    summary,
    csv,
    gui,
}

Args :: struct {
    command: Command,
    inner: union {
        Add_Args,
        Start_Args,
        Summary_Args,
        Csv_Args,
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

Csv_Args :: struct {
    using base: Summary_Args,
    user_name: string,
}

print_usage :: proc() {
    fmt.println("Usage: odin <command> [<args>]")
    fmt.println("Commands:")
    for command in Command {
        switch command {
            case .init:    fmt.println("    init                                  Initialize './trecker_session.ini'. This is the first command you will have to use.")
            case .add:     fmt.println("    add     <project_id> <project_name>   Add a new project to the list.")
            case .start:   fmt.println("    start   <project_id>                  Start tracking time for the given project.")
            case .list:    fmt.println("    list                                  List all known projects.")
            case .summary: fmt.println("    summary <month> <year>                Print work summary in human readable format.")
            case .csv:     fmt.println("    csv     <month> <year> <user_name>    Print work summary in CSV format specific to how my employer needs it.")
            case .gui:     fmt.println("    gui                                   Start the graphical user interface.")
        }
    }
}

parse_args :: proc(raw_args: []string) -> (args: Args, ok: bool) {
    if len(raw_args) < 1 {
        fmt.println("No args were passed.")
        print_usage()
        return {}, false
    }

    command_str := raw_args[0]

    for command in Command {
        if strings.compare(command_str, reflect.enum_string(command)) == 0 {
            args.command = command

            switch command {
            case .init:
                ok = true
            case .add:
                if len(raw_args) < 2 {
                    fmt.println("Missing argument: project_id")
                    print_usage()
                }
                else if len(raw_args) < 3 {
                    fmt.println("Missing argument: project_name")
                    print_usage()
                } else {                
                    args.inner = Add_Args {
                        project_id = raw_args[1],
                        project_name = raw_args[2],
                    }
                    ok = true
                }
            case .start:
                if len(raw_args) < 2 {
                    fmt.println("Missing argument: project_id")
                    print_usage()
                    return {}, false
                } else {
                    args.inner = Start_Args { project_id = raw_args[1] }
                    ok = true
                }
            case .list:
                ok = true
            case .summary:
                if len(raw_args) < 2 {
                    fmt.println("Missing argument: month")
                    print_usage()
                } else if len(raw_args) < 3 {
                    fmt.println("Missing argument: year")
                    print_usage()
                } else {
                    args.inner = Summary_Args {
                        month = raw_args[1],
                        year = raw_args[2],
                    }
                    ok = true
                }
            case .csv:
                if len(raw_args) < 2 {
                    fmt.println("Missing argument: month")
                    print_usage()
                } else if len(raw_args) < 3 {
                    fmt.println("Missing argument: year")
                    print_usage()
                } else if len(raw_args) < 4 {
                    fmt.println("Missing argument: user_name")
                    print_usage()
                } else {
                    args.inner = Csv_Args {
                        month = raw_args[1],
                        year = raw_args[2],
                        user_name = raw_args[3],
                    }
                    ok = true
                }
            case .gui:
                ok = true
            }
        }
    }

    if args.command == nil {
        fmt.printfln("Unknown command: '%v'.", command_str)
        print_usage()
    }
    return
}

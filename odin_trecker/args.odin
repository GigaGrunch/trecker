package trecker

import "core:strings"
import "core:fmt"

Args :: struct {
    type: enum {
        init,
    },
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

    fmt.printfln("Unknown command: '%v'.", command_str)
    return {}, false
}

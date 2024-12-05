package trecker

import "core:os"
import "core:fmt"

main :: proc() {
    args, ok := parse_args(os.args[1:])
    if !ok do os.exit(1)
    
    switch args.type {
        case .init: command_init()
    }
}

session_file_path :: "trecker_session.ini"

command_init :: proc() {
    if os.exists(session_file_path) {
        fmt.printfln("Session file already exists at '%v'.", session_file_path)
        os.exit(1)
    }
    
    store := Store{}
    serialized := serialize_store(store)
    os.write_entire_file(session_file_path, serialized)
}

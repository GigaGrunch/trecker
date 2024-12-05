package trecker

import "core:os"
import "core:fmt"

main :: proc() {
    args, args_ok := parse_args(os.args[1:])
    if !args_ok do os.exit(1)
    
    switch args.type {
        case .init: command_init()
        case .add: command_add(args.inner.(AddArgs))
    }
}

session_file_path :: "trecker_session.ini"

command_init :: proc() {
    if os.exists(session_file_path) {
        fmt.printfln("Session file already exists at '%v'.", session_file_path)
        os.exit(1)
    }
    
    store := Store{}
    write_ok := write_store_file(store)
    if !write_ok do os.exit(1)
}

command_add :: proc(args: AddArgs) {
    // TODO: check for duplicates

    serialized, file_ok := os.read_entire_file(session_file_path)
    if !file_ok {
        fmt.printfln("Failed to read file at '%v'", session_file_path)
        os.exit(1)
    }
    store, store_ok := deserialize_store(serialized)
    if !store_ok do os.exit(1)
    
    project := Project {
        name = args.project_name,
        id = args.project_id,
    }
    
    append(&store.projects, project)
    
    write_ok := write_store_file(store)
    if !write_ok do os.exit(1)
}

write_store_file :: proc(store: Store) -> bool {
    serialized := serialize_store(store)
    write_ok := os.write_entire_file(session_file_path, serialized)
    if !write_ok {
        fmt.printfln("Failed to write file at '%v'.", session_file_path)
        return false
    }
    return true
}

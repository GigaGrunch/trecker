package trecker

import "core:os"
import "core:fmt"
import "core:strings"
import "core:time"

main :: proc() {
    args, args_ok := parse_args(os.args[1:])
    if !args_ok do os.exit(1)
    
    switch args.type {
        case .init: command_init()
        case .add: command_add(args.inner.(AddArgs))
        case .start: command_start(args.inner.(StartArgs))
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
    store, store_ok := read_store_file()
    if !store_ok do os.exit(1)
    
    for other_project in store.projects {
        if strings.compare(other_project.id, args.project_id) == 0 {
            fmt.printfln("Project with id '%v' is already defined.", args.project_id)
            os.exit(1)
        }
    }
    
    project := Project {
        name = args.project_name,
        id = args.project_id,
    }
    
    append(&store.projects, project)
    
    write_ok := write_store_file(store)
    if !write_ok do os.exit(1)
}

command_start :: proc(args: StartArgs) {
    store, store_ok := read_store_file()
    if !store_ok do os.exit(1)
    
    project_ok := false
    for project in store.projects {
        if strings.compare(project.id, args.project_id) == 0 {
            project_ok = true
            break
        }
    }
    if !project_ok {
        fmt.printfln("Project with id '%v' does not exist.", args.project_id)
        os.exit(1)
    }
    
    entry_index := len(store.entries)
    append(&store.entries, Entry {
        project_id = args.project_id,
        start = time.now(),
        end = time.now(),
    })
    entry := &store.entries[entry_index]
    
    last_serialization_minute := -1
    duration_buf: [len("00:00:00")]u8
    
    for {
        defer free_all(context.temp_allocator)
    
        duration := time.since(entry.start)
        duration_str := time.duration_to_string_hms(duration, duration_buf[:])
    
        clear_line :: "\x1b[2K\r";
        fmt.printf("%v%v\r", clear_line, duration_str)
        
        full_minute := int(time.duration_minutes(duration))
        if full_minute > last_serialization_minute {
            entry.end = time.now()
            last_serialization_minute = full_minute
            write_store_file(store)
        }
        
        time.sleep(1 * time.Second)
    }
}

read_store_file :: proc() -> (Store, bool) {
    serialized, file_ok := os.read_entire_file(session_file_path)
    if !file_ok {
        fmt.printfln("Failed to read file at '%v'.", session_file_path)
        return {}, false
    }
    return deserialize_store(serialized)
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

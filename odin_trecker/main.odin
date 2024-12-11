package trecker

import "core:os"
import "core:fmt"
import "core:strings"
import "core:time"
import "core:mem"

main :: proc() {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)
    defer deinit_tracking_allocator(&track)

    args, args_ok := parse_args(os.args[1:])
    if !args_ok do os.exit(1)
    
    switch args.type {
    case .init: command_init()
    case .add: command_add(args.inner.(AddArgs))
    case .start: command_start(args.inner.(StartArgs))
    case .list: command_list()
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
    
    project: Project
    for other_project in store.projects {
        if strings.compare(other_project.id, args.project_id) == 0 {
            project = other_project
            break
        }
    }
    if project == {} {
        fmt.printfln("Project with id '%v' does not exist.", args.project_id)
        os.exit(1)
    }
    
    start_year, start_month, start_day := time.date(time.now())    
    initial_today_duration: time.Duration
    for other in store.entries {
        other_year, other_month, other_day := time.date(other.start)
        if start_year == other_year && start_month == other_month && start_day == other_day {
            initial_today_duration += time.diff(other.start, other.end)
        }
    }
    
    entry_index := len(store.entries)
    append(&store.entries, Entry {
        project_id = args.project_id,
        start = time.now(),
        end = time.now(),
    })
    entry := &store.entries[entry_index]
    
    last_serialization_minute := 0
    duration_buf: [len("00:00:00")]u8
    today_duration_buf: [len("00:00:00")]u8
    
    for {
        duration := time.since(entry.start)
        duration_str := time.duration_to_string_hms(duration, duration_buf[:])
        today_duration := initial_today_duration + duration
        today_duration_str := time.duration_to_string_hms(today_duration, today_duration_buf[:])
    
        clear_line :: "\x1b[2K\r"
        fmt.printf("%v%v %v (%v)\r", clear_line, project.name, duration_str, today_duration_str)
        fmt.printf("\x1b]0;trecker %v %v\x07", project.id, today_duration_str)
        
        full_minute := int(time.duration_minutes(duration))
        if full_minute > last_serialization_minute {
            entry.end = time.now()
            last_serialization_minute = full_minute
            write_store_file(store)
        }
        
        time.sleep(1 * time.Second)
    }
}

command_list :: proc() {
    store, store_ok := read_store_file()
    if !store_ok do os.exit(1)
    
    fmt.printfln("%v registered projects:", len(store.projects))
    
    for project in store.projects {
        fmt.printfln("%v: %v", project.id, project.name)
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
    serialized := store_serialize(store)
    defer delete(serialized)
    write_ok := os.write_entire_file(session_file_path, serialized)
    if !write_ok {
        fmt.printfln("Failed to write file at '%v'.", session_file_path)
        return false
    }
    return true
}

deinit_tracking_allocator :: proc(track: ^mem.Tracking_Allocator) {
    if len(track.allocation_map) > 0 {
        fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map {
            fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
        }
    }
    if len(track.bad_free_array) > 0 {
        fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array {
            fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
        }
    }
    mem.tracking_allocator_destroy(track)
}

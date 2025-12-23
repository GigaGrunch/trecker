package trecker_lib

import "core:os"
import "core:fmt"
import "core:time"
import "core:strings"

STORE_VERSION :: 2
STORE_VERSION_STR :: "2"
TIME_FORMAT :: "yyyy-MM-ddThh:mm:ss"
SESSION_FILE_PATH :: "trecker_session.ini"

Store :: struct {
    projects: [dynamic]Project,
    entries: [dynamic]Entry,
}

Project :: struct {
    id: string,
    name: string,
}

Entry :: struct {
    project_id: string,
    start: time.Time,
    end: time.Time,
}

read_store_file :: proc() -> (Store, bool) {
    serialized, file_ok := os.read_entire_file(SESSION_FILE_PATH)
    defer delete(serialized)
    if !file_ok {
        fmt.printfln("Failed to read file at '%v'.", SESSION_FILE_PATH)
        return {}, false
    }
    return store_deserialize(transmute(string)serialized)
}

write_store_file :: proc(store: Store) -> bool {
    serialized := store_serialize(store)
    defer delete(serialized)
    write_ok := os.write_entire_file(SESSION_FILE_PATH, serialized)
    if !write_ok {
        fmt.printfln("Failed to write file at '%v'.", SESSION_FILE_PATH)
        return false
    }
    return true
}

store_destroy :: proc(store: ^Store) {
    for project in store.projects {
        delete(project.id)
        delete(project.name)
    }
    for entry in store.entries do delete(entry.project_id)
    delete(store.projects)
    delete(store.entries)
    store^ = {}
}

get_today_duration :: proc(store: Store, project: Project) -> (today_duration: time.Duration) {
    year, month, day := time.date(time.now())    
    for entry in store.entries {
        if strings.compare(entry.project_id, project.id) == 0 {
            other_year, other_month, other_day := time.date(entry.start)
            if year == other_year && month == other_month && day == other_day {
                today_duration += time.diff(entry.start, entry.end)
            }
        }
    }
    return
}

store_serialize :: proc(store: Store) -> []u8 {
    builder := strings.builder_make()
    
    strings.write_string(&builder, "version: ") // TODO: these are the same consts as in deserialize
    strings.write_int(&builder, STORE_VERSION)
    strings.write_string(&builder, "\n\n")
    
    for project in store.projects {
        strings.write_string(&builder, "project: ")
        strings.write_string(&builder, project.id)
        strings.write_string(&builder, " '")
        strings.write_string(&builder, project.name)
        strings.write_string(&builder, "'\n")
    }
    strings.write_string(&builder, "\n")
    
    for entry in store.entries {
        start_str, start_ok := time.time_to_rfc3339(entry.start)
        end_str, end_ok := time.time_to_rfc3339(entry.end)
        defer {
            delete(start_str)
            delete(end_str)
        }
        if !start_ok || !end_ok {
            fmt.printfln("Failed to serialize time stamps for entry: %v", entry)
            os.exit(1)
        }
        
        if time.duration_minutes(time.diff(entry.start, entry.end)) > 1 {
            strings.write_string(&builder, "entry: ")
            strings.write_string(&builder, entry.project_id)
            strings.write_string(&builder, " ")
            strings.write_string(&builder, start_str[:len(TIME_FORMAT)])
            strings.write_string(&builder, "..")
            strings.write_string(&builder, end_str[:len(TIME_FORMAT)])
            strings.write_string(&builder, "\n")
        }
    }
    
    return builder.buf[:]
}

store_deserialize :: proc(serialized: string) -> (res: Store, ok: bool) {
    store: Store
    
    version_key :: "version"
    version_value: string
    
    project_key :: "project"
    entry_key :: "entry"
    
    serialized_mut := serialized
    line_number := 0 // TODO: are empty lines skipped?
    for line in strings.split_lines_iterator(&serialized_mut) {
        line_number += 1
        if len(line) == 0 do continue
        
        line_mut := line
        key_raw, key_ok := strings.split_iterator(&line_mut, ":")
        key := strings.trim_space(key_raw)
        value := strings.trim_space(line_mut)
        if !key_ok || len(key) == 0 || len(value) == 0 {
            fmt.printfln("Failed to parse ini key-value pair from line %v: '%v'.", line_number, line)
            return {}, false
        }
        
        if strings.compare(key, version_key) == 0 {
            version_value = value
        } else if strings.compare(key, project_key) == 0 {
            id, id_ok := strings.split_iterator(&value, " ")
            name := strings.trim(value, "'")
            if !id_ok || len(name) == 0 {
                fmt.printfln("Failed to parse project id and name from line %v: '%v'.", line_number, line)
                return {}, false
            }
            store_add_project(&store, id, name)
        } else if strings.compare(key, entry_key) == 0 {
            project_id, id_ok := strings.split_iterator(&value, " ")
            time_range := value
            if !id_ok || len(project_id) == 0 || len(time_range) == 0 {
                fmt.printfln("Failed to parse project id and time range from line %v: '%v'.", line_number, line)
                return {}, false
            }
            
            start_str, start_ok := strings.split_iterator(&time_range, "..")
            end_str := time_range
            if !start_ok || len(start_str) == 0 || len(end_str) == 0 {
                fmt.printfln("Failed to parse time range from '%v' in line %v: '%v'.", time_range, line_number, line)
                return {}, false
            }
            
            start := parse_time(start_str) or_return
            end := parse_time(end_str) or_return
            
            append(&store.entries, Entry {
                project_id = fmt.aprint(project_id),
                start = start,
                end = end,
            })
        } else {
            fmt.printfln("Unknown ini key '%v' found in line %v: '%v'.", key, line_number, line)
            return {}, false
        }
    }
    
    if version_value == "" {
        fmt.printfln("Did not find ini key '%v' in serialized data.", version_key)
        return {}, false
    }
    
    if strings.compare(version_value, STORE_VERSION_STR) != 0 {
        fmt.printfln("Serialized store version is '%v', but only '%v' is supported.", version_value, STORE_VERSION_STR)
        return {}, false
    }
    
    return store, true
}

store_add_project :: proc(store: ^Store, id, name: string) {
    append(&store.projects, Project {
        id = fmt.aprint(id),
        name = fmt.aprint(name),
    })
}

store_add_entry :: proc(store: ^Store, project_id: string, start, end: time.Time) -> ^Entry {
    index := len(store.entries)
    append(&store.entries, Entry {
        project_id = fmt.aprint(project_id),
        start = start,
        end = end,
    })
    return &store.entries[index]
}

parse_time :: proc(str: string) -> (res: time.Time, ok: bool) {
    if len(str) != len(TIME_FORMAT) {
        fmt.printfln("Time string '%v' (len=%v) has invalid format. '%v' (len=%v) is expected", str, len(str), TIME_FORMAT, len(TIME_FORMAT))
        return {}, false
    }
    
    suffix :: "+00:00"
    fixed: [len(TIME_FORMAT) + len(suffix)]u8
    
    copy(fixed[:len(TIME_FORMAT)], str)
    copy(fixed[len(TIME_FORMAT):], suffix)

    result, _, _ := time.rfc3339_to_time_and_offset(transmute(string)fixed[:])
    
    if result == {} {
        fmt.printfln("Failed to parse time from '%v'.", str)
        return {}, false
    }
    
    return result, true
}

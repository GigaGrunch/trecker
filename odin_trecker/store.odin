package trecker

import "core:strings"
import "core:fmt"
import "core:time"
import "core:os"

store_version :: 2
store_version_str :: "2"

Store :: struct {
    projects: [dynamic]Project,
    entries: [dynamic]Entry,
}

Project :: struct {
    name: string,
    id: string,
}

Entry :: struct {
    project_id: string,
    start: time.Time,
    end: time.Time,
}

serialize_store :: proc(store: Store) -> []u8 {
    context.allocator = context.temp_allocator

    builder := strings.builder_make()
    
    strings.write_string(&builder, "version: ") // TODO: these are the same consts as in deserialize
    strings.write_int(&builder, store_version)
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
        strings.write_string(&builder, "entry: ")
        strings.write_string(&builder, entry.project_id)
        strings.write_string(&builder, " ")
        // TODO: timezone
        start_str, start_ok := time.time_to_rfc3339(entry.start)
        end_str, end_ok := time.time_to_rfc3339(entry.end)
        if !start_ok || !end_ok {
            fmt.printfln("Failed to serialize time stamps for entry: %v", entry)
            os.exit(1)
        }
        strings.write_string(&builder, start_str)
        strings.write_string(&builder, "..")
        strings.write_string(&builder, end_str)
        strings.write_string(&builder, "\n")
    }
    
    return builder.buf[:]
}

deserialize_store :: proc(serialized: []u8) -> (Store, bool) {
    lines_it := tokenize(serialized, "\r\n")
    
    result: Store
    
    version_key :: "version"
    version_value: string
    
    project_key :: "project"
    entry_key :: "entry"
    
    for line, line_index in next_token_indexed(&lines_it) {
        key_value_split := strings.split_n(line, ":", 2)
        if len(key_value_split) != 2 {
            fmt.printfln("Failed to parse ini key-value pair from line %v: '%v'.", line_index + 1, line)
            return {}, false
        }
        
        key := strings.trim_space(key_value_split[0])
        value := strings.trim_space(key_value_split[1])
        
        if strings.compare(key, version_key) == 0 {
            version_value = value
        }
        else if strings.compare(key, project_key) == 0 {
            project_it := tokenize(value, " ")
            project_id, id_ok := next_token(&project_it)
            wrapped_project_name, name_ok := next_token(&project_it)
            if !id_ok || !name_ok {
                fmt.printfln("Failed to parse project id and name from line %v: '%v'.", line_index + 1, line)
                return {}, false
            }
            project_name := strings.trim(wrapped_project_name, "'")
            append(&result.projects, Project {
                name = project_name,
                id = project_id,
            })
        }
        else if strings.compare(key, entry_key) == 0 {
            entry_it := tokenize(value, " ")
            project_id, id_ok := next_token(&entry_it)
            time_range, time_ok := next_token(&entry_it)
            if !id_ok || !time_ok {
                fmt.printfln("Failed to parse project id and time range from line %v: '%v'.", line_index + 1, line)
                return {}, false
            }
            
            range_split := strings.split(time_range, "..")
            if len(range_split) != 2 {
                fmt.printfln("Failed to parse time range from '%v' in line %v: '%v'.", time_range, line_index + 1, line)
                return {}, false
            }
            
            start, _ := time.rfc3339_to_time_utc(range_split[0])
            end, _ := time.rfc3339_to_time_utc(range_split[1])
            
            append(&result.entries, Entry {
                project_id = project_id,
                start = start,
                end = end,
            })
        }
        else {
            fmt.printfln("Unknown ini key '%v' found in line %v: '%v'.", key, line_index + 1, line) // TODO: the line numbers aren't correct because empty lines are skipped
            return {}, false
        }
    }
    
    if version_value == "" {
        fmt.printfln("Did not find ini key '%v' in serialized data.", version_key)
        return {}, false
    }
    
    if strings.compare(version_value, store_version_str) != 0 {
        fmt.printfln("Serialized store version is '%v', but only '%v' is supported.", version_value, store_version_str)
        return {}, false
    }
    
    return result, true
}

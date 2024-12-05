package trecker

import "core:strings"
import "core:fmt"

store_version :: 2
store_version_str :: "2"

Store :: struct {
    projects: [dynamic]Project,
}

Project :: struct {
    name: string,
    id: string,
}

serialize_store :: proc(store: Store) -> []u8 {
    builder := strings.builder_make()
    
    strings.write_string(&builder, "version: ")
    strings.write_int(&builder, store_version)
    strings.write_string(&builder, "\n\n")
    
    for project in store.projects {
        strings.write_string(&builder, "project: ")
        strings.write_string(&builder, project.id)
        strings.write_string(&builder, " '")
        strings.write_string(&builder, project.name)
        strings.write_string(&builder, "'\n")
    }
    
    return builder.buf[:]
}

deserialize_store :: proc(serialized: []u8) -> (Store, bool) {
    lines_it := tokenize(serialized, "\r\n")
    
    result: Store
    
    version_key :: "version"
    version_value: string
    
    project_key :: "project"
    
    for line, line_index in next_token_indexed(&lines_it) {
        key_value_it := tokenize(line, ":")
        key, key_ok := next_token(&key_value_it)
        value, value_ok := next_token(&key_value_it)
        if !key_ok || !value_ok {
            fmt.printfln("Failed to parse ini key-value pair from line %v: '%v'.", line_index + 1, line)
            return {}, false
        }
        
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

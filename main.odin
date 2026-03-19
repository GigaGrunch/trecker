package trecker

import "core:os"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:flags"

startup_store: Store

main :: proc() {
	if err := string_lookup_init(); err != .None {
		fmt.printfln("string_lookup_init failed with '%v'", err);
		os.exit(1)
	}

	{ // load store
		defer free_all(context.temp_allocator)

		file_data, read_file_err := os.read_entire_file(STORE_PATH, context.temp_allocator)
		switch read_file_err {
			case nil:
				Parsed_Line :: struct {
					line_num: int,
					raw: string,
					value: string,
				}
				Key :: string
				parsed_lines := make(map[Key][dynamic]Parsed_Line, context.temp_allocator)
				parsed_lines["version"] = make([dynamic]Parsed_Line, context.temp_allocator)
				parsed_lines["project"] = make([dynamic]Parsed_Line, context.temp_allocator)
				parsed_lines["entry"] = make([dynamic]Parsed_Line, context.temp_allocator)

				file_it := transmute(string)file_data
				line_num := 1
				for line in strings.split_lines_iterator(&file_it) {
					trimmed_line := strings.trim_space(line)
					line_it := trimmed_line
					if line_it != "" {
						key, _ := strings.split_iterator(&line_it , ": ")
						value := line_it
						parsed: Parsed_Line
						parsed.line_num = line_num
						parsed.raw = trimmed_line
						parsed.value = strings.trim_space(value)
						if key not_in parsed_lines {
							parsed_lines[key] = make([dynamic]Parsed_Line, context.temp_allocator)
						}
						append(&parsed_lines[key], parsed)
					}
					line_num += 1
				}

				version_ok := false
				versions := parsed_lines["version"]
				if len(versions) == 1 {
					line := versions[0]
					if strings_equal(line.value, STORE_VERSION) {
						version_ok = true
					} else {
						fmt.printfln("[%v:%v] expected version '%v', but found '%v'", STORE_PATH, line.line_num, STORE_VERSION, line.value)
					}
				} else {
					fmt.printfln("expected 1 version entries, but found %v", len(versions))
				}
				delete_key(&parsed_lines, "version")

				projects_ok := true
				for line in parsed_lines["project"] {
					project_ok := true
					
					line_it := line.value
					id, _ := strings.split_iterator(&line_it, " ")
					id = strings.trim_space(id)
					name := line_it
					name = strings.trim_space(name)
					name = strings.trim(name, "'")

					if id == "" {
						project_ok = false
						fmt.printfln("[%v:%v] project ID is empty", STORE_PATH, line.line_num)
					}
					if id in startup_store.projects {
						project_ok = false
						fmt.printfln("[%v:%v] project ID already defined", STORE_PATH, line.line_num)
					}

					if name == "" {
						project_ok = false
						fmt.printfln("[%v:%v] project name is empty", STORE_PATH, line.line_num)
					}

					if project_ok {
						project: Project
						project.name = stable_string(name)
						startup_store.projects[stable_string(id)] = project
					}

					projects_ok &= project_ok
				}
				delete_key(&parsed_lines, "project")

				entries_ok := true
				for line in parsed_lines["entry"] {
					entry_ok := true

					parse_time :: proc(value: string) -> time.Time {
						parse_str := fmt.tprintf("%v+00:00", value)
						result, _, _ := time.rfc3339_to_time_and_offset(parse_str)
						return result
					}

					line_it := line.value
					project_id, _ := strings.split_iterator(&line_it, " ")
					project_id = strings.trim_space(project_id)
					time_range := line_it
					time_it := time_range
					start_str, _ := strings.split_iterator(&time_it, "..")
					start_str = strings.trim_space(start_str)
					end_str := strings.trim_space(time_it)
					start_time := parse_time(start_str)
					end_time := parse_time(end_str)

					if project_id == "" {
						entry_ok = false
						fmt.printfln("[%v:%v] project id is empty", STORE_PATH, line.line_num)
					}
					else if project_id not_in startup_store.projects {
						entry_ok = false
						fmt.printfln("[%v:%v] project '%v' is not defined", STORE_PATH, line.line_num, project_id)
					}

					if start_time == {} || end_time == {} {
						entry_ok = false
						fmt.printfln("[%v:%v] failed to parse time range from '%v'", STORE_PATH, line.line_num, time_range)
					}

					if entry_ok {
						entry: Entry
						entry.project_id = stable_string(project_id)
						entry.start = start_time
						entry.end = end_time
					}

					entries_ok &= entry_ok
				}
				delete_key(&parsed_lines, "entry")

				has_unknown_keys := len(parsed_lines) > 0
				for key in parsed_lines {
					for line in parsed_lines[key] {
						fmt.printfln("[%v:%v] unknown key '%v'", STORE_PATH, line.line_num, key)
					}
				}

				if !version_ok || !projects_ok || !entries_ok || has_unknown_keys {
					os.exit(1)
				}
			case .Not_Exist:
				fmt.printfln("starting with a fresh session because '%v' does not exist", STORE_PATH)
			case:
				fmt.printfln("failed to read file '%v' with error '%v'", STORE_PATH, read_file_err)
				os.exit(1)
		}

		for project_id in startup_store.projects {
			project := startup_store.projects[project_id]
			assert(project_id in string_index_lookup)
			assert(project.name in string_index_lookup)
		}

		for entry in startup_store.entries {
			assert(entry.project_id in startup_store.projects)
			assert(entry.project_id in string_index_lookup)
		}
	}

	command: string
	if len(os.args) > 1 {
		command = os.args[1]
	}

	if command == "" {
		fmt.println("no command given")
	} else if strings_equal(command, "list") {
		args: struct {}
		parse_err := flags.parse(&args, os.args[2:])

		if parse_err == nil {
			fmt.printfln("Store contains %v projects:", len(startup_store.projects))
			for project_id in startup_store.projects {
				project := startup_store.projects[project_id]
				fmt.printfln("  %v: '%v'", project_id, project.name)
			}
		} else {
			switch err in parse_err {
			case flags.Parse_Error:
				fmt.println(err.message)
			case flags.Help_Request:
			case flags.Validation_Error:
				fmt.println(err.message)
			case flags.Open_File_Error:
				fmt.println(err)
			}
		}
	} else {
		fmt.printfln("unknown command '%v'", command)
	}
}

strings_equal :: proc(a, b: string) -> bool {
	return strings.compare(a, b) == 0
}

STORE_VERSION :: "2"
STORE_PATH :: "trecker_session.ini"

Project_ID :: string

Store :: struct {
	projects: map[Project_ID]Project,
	entries: []Entry,
}

Project :: struct {
	name: string,
}

Entry :: struct {
	project_id: Project_ID,
	start: time.Time,
	end: time.Time,
}

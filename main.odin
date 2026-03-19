package trecker

import "core:os"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:slice"

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

					line_it := line.value
					project_id, _ := strings.split_iterator(&line_it, " ")
					project_id = strings.trim_space(project_id)
					time_range := line_it
					start, end, range_ok := parse_time_range(time_range)

					if project_id == "" {
						entry_ok = false
						fmt.printfln("[%v:%v] project id is empty", STORE_PATH, line.line_num)
					}
					else if project_id not_in startup_store.projects {
						entry_ok = false
						fmt.printfln("[%v:%v] project '%v' is not defined", STORE_PATH, line.line_num, project_id)
					}

					if !range_ok {
						entry_ok = false
						fmt.printfln("[%v:%v] failed to parse time range from '%v'", STORE_PATH, line.line_num, time_range)
					}

					if entry_ok {
						entry: Entry
						entry.project_id = stable_string(project_id)
						entry.start = start
						entry.end = end
						append(&startup_store.entries, entry)
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

	Add_Entry :: Entry

	parsed_command: union {
		Add_Entry,
	}

	{ // command parsing
		command_str := take_next_arg()
		if command_str == "" {
			fmt.println("'command' is missing")
		} else if strings_equal(command_str, "add-entry") {
			project_id := take_next_arg()
			project_ok := project_id in startup_store.projects
			if project_id == "" {
				fmt.printfln("'project-id' is missing")
			} else if !project_ok {
				fmt.printfln("project '%v' is not defined", project_id)
			}

			time_range := take_next_arg()
			start, end, range_ok := parse_time_range(time_range)
			if time_range == "" {
				fmt.printfln("'time-range' is missing")
			} else if !range_ok {
				fmt.printfln("failed to parse time range from '%v'", time_range)
			}

			if project_ok && range_ok {
				add_entry: Add_Entry
				add_entry.project_id = stable_string(project_id)
				add_entry.start = start
				add_entry.end = end
				parsed_command = add_entry
			}
		} else {
			fmt.printfln("unknown command '%v'", command_str)
		}

		if parsed_command == nil {
			fmt.println("usage: TODO")
			os.exit(1)
		}
	}

	{ // execute
		switch command in parsed_command {
		case Add_Entry:
			output_store: Store
			for project_id in startup_store.projects {
				project := startup_store.projects[project_id]
				output_store.projects[project_id] = project
			}
			for entry in startup_store.entries {
				append(&output_store.entries, entry)
			}

			new_entry := command
			append(&output_store.entries, new_entry)
		}
	}
}

take_next_arg :: proc() -> (arg: string) {
	@static next_arg_i := 1
	if len(os.args) > next_arg_i {
		arg = os.args[next_arg_i]
	}
	next_arg_i += 1
	return
}

parse_time_range :: proc(value: string) -> (start, end: time.Time, ok: bool) {
	time_it := value
	start_str, _ := strings.split_iterator(&time_it, "..")
	start_str = strings.trim_space(start_str)
	start_str = fmt.tprintf("%v+00:00", start_str)
	start_time, _, _ := time.rfc3339_to_time_and_offset(start_str)
	end_str := strings.trim_space(time_it)
	end_str = fmt.tprintf("%v+00:00", end_str)
	end_time, _, _ := time.rfc3339_to_time_and_offset(end_str)
	start, end = start_time, end_time
	ok = start != {} && end != {}
	return
}

strings_equal :: proc(a, b: string) -> bool {
	return strings.compare(a, b) == 0
}

STORE_VERSION :: "2"
STORE_PATH :: "trecker_session.ini"

Project_ID :: string

Store :: struct {
	projects: map[Project_ID]Project,
	entries: [dynamic]Entry,
}

Project :: struct {
	name: string,
}

Entry :: struct {
	project_id: Project_ID,
	start: time.Time,
	end: time.Time,
}

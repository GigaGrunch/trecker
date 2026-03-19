package trecker

import "core:os"
import "core:fmt"
import "core:time"
import "core:strings"
import "core:flags"
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

	{ // command parsing
		command, sub_command: string
		if len(os.args) > 1 {
			command = os.args[1]
		}
		if len(os.args) > 2 {
			sub_command = os.args[2]
		}

		if command == "" {
			fmt.println("no command given")
		} else if strings_equal(command, "list") {
			args: struct {}
			parse_err := flags.parse(&args, os.args[2:])

			if parse_err == nil {
				sorted_ids := make([dynamic]string, allocator=context.temp_allocator, cap=len(startup_store.projects), len=0)
				for id in startup_store.projects {
					append(&sorted_ids, id)
				}
				slice.sort(sorted_ids[:])

				fmt.printfln("Store contains %v projects:", len(sorted_ids))
				for project_id in sorted_ids {
					project := startup_store.projects[project_id]
					fmt.printfln("  %v: '%v'", project_id, project.name)
				}
			} else {
				switch err in parse_err {
				case flags.Parse_Error:
					fmt.println(err.message)
				case flags.Help_Request: // TODO
				case flags.Validation_Error:
					fmt.println(err.message)
				case flags.Open_File_Error:
					fmt.println(err)
				}
			}
		} else if strings_equal(command, "add") {
			if sub_command == "" {
				fmt.printfln("no sub command for `%v` given", command)
			} else if strings_equal(sub_command, "entry") {
				args: struct {
					project_id: Project_ID `args:"pos=0,required"`,
					time_range: string `args:"pos=1,required"`,
				}
				parse_err := flags.parse(&args, os.args[3:])
				if parse_err == nil {
					project_ok := args.project_id in startup_store.projects
					start, end, range_ok := parse_time_range(args.time_range)

					if !project_ok {
						fmt.printfln("project '%v' is not defined", args.project_id)
					}
					if !range_ok {
						fmt.printfln("failed to parse time range from '%v'", args.time_range)
					}

					if project_ok && range_ok {
						output_store: Store
						output_store.projects.allocator = context.temp_allocator
						output_store.entries.allocator = context.temp_allocator
						
						for project_id in startup_store.projects {
							output_store.projects[project_id] = startup_store.projects[project_id]
						}

						for entry in startup_store.entries {
							append(&output_store.entries, entry)
						}

						new_entry: Entry
						new_entry.project_id = args.project_id
						new_entry.start = start
						new_entry.end = end
						append(&output_store.entries, new_entry)

						// TOOD: serialize
					} else {
						os.exit(1)
					}
				} else {
					switch err in parse_err {
					case flags.Parse_Error:
						fmt.println(err.message)
					case flags.Help_Request: // TODO
					case flags.Validation_Error:
						fmt.println(err.message)
					case flags.Open_File_Error:
						fmt.println(err)
					}
				}
			} else {
				fmt.printfln("unknown `%v` sub-command `%v`", command, sub_command)
			}
		} else {
			fmt.printfln("unknown command `%v`", command)
		}
	}
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

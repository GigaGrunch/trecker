package trecker

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:time"
import "core:math"
import "core:mem"
import "core:sort"
import "core:slice"
import "core:c/libc"
import rl "vendor:raylib"

got_interrupt_signal := false

handle_interrupt_signal :: proc "c" (_: i32) {
    if got_interrupt_signal do os.exit(1)
    got_interrupt_signal = true
}

main :: proc() {
    // libc.signal(libc.SIGINT, handle_interrupt_signal)

    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)
    defer deinit_tracking_allocator(&track)

    args, args_ok := parse_args(os.args[1:])
    if !args_ok do os.exit(1)
    
    switch args.command {
        case .init: command_init()
        case .add: command_add(args.inner.(Add_Args))
        case .start: command_start(args.inner.(Start_Args))
        case .list: command_list()
        case .summary: command_summary(args.inner.(Summary_Args))
        case .csv: command_csv(args.inner.(Csv_Args))
        case .gui: command_gui()
    }
}

session_file_path :: "trecker_session.ini"

command_gui :: proc() {
    store, store_ok := read_store_file()
    defer store_destroy(&store)
    if !store_ok do os.exit(1)

    rl.SetTraceLogLevel(.WARNING)
    rl.SetConfigFlags({ .WINDOW_RESIZABLE })
    rl.SetTargetFPS(60)
    rl.InitWindow(1280, 720, "trecker")

    scale_factor := rl.GetWindowScaleDPI().x
    font_size := 24 * scale_factor
    font := rl.LoadFontEx("RobotoCondensed-Regular.ttf", i32(font_size), nil, 0)
    rl.GuiSetStyle(.DEFAULT, i32(rl.GuiDefaultProperty.TEXT_SIZE), i32(font_size))
    rl.GuiSetFont(font)

    scroll_value := f32(0)
    scroll_content_size := rl.Vector2 { 1, 1 }

    for !rl.WindowShouldClose() {
        scroll_value += rl.GetMouseWheelMove() * 20
        scroll_value = clamp(scroll_value, f32(rl.GetScreenHeight()) - scroll_content_size.y, 0)

        scroll_render_target := rl.LoadRenderTexture(i32(scroll_content_size.x), i32(scroll_content_size.y))
        defer rl.UnloadRenderTexture(scroll_render_target)
        scroll_content_size.x = f32(rl.GetScreenWidth())
        scroll_content_size.y = 0

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        {
            rl.BeginTextureMode(scroll_render_target)
            {
                padding := 10 * scale_factor
                project_y := padding

                for project in store.projects {
                    rect := rl.Rectangle {
                        x = padding,
                        y = project_y,
                        width = 400,
                        height = font_size,
                    }
                    rl.GuiLabel(rect, fmt.ctprint(project.name))

                    rect.x += rect.width + padding
                    duration := get_today_duration(store, project)
                    duration_buf: [len("00:00:00")]u8
                    duration_str := time.duration_to_string_hms(duration, duration_buf[:])
                    rl.GuiLabel(rect, fmt.ctprintf("%v", duration_str))

                    project_y += rect.height + padding
                }

                scroll_content_size.y = project_y
            }
            rl.EndTextureMode()

            // texture has to be flipped for some reason
            rl.DrawTexturePro(scroll_render_target.texture,
                source = rl.Rectangle { width=scroll_content_size.x, height=-scroll_content_size.y },
                dest = rl.Rectangle { y=scroll_value, width=scroll_content_size.x, height=scroll_content_size.y },
                origin = {},
                rotation = 0,
                tint = rl.WHITE)
        }
        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
}

command_init :: proc() {
    if os.exists(session_file_path) {
        fmt.printfln("Session file already exists at '%v'.", session_file_path)
        os.exit(1)
    }
    
    store := Store{}
    write_ok := write_store_file(store)
    if !write_ok do os.exit(1)
}

command_add :: proc(args: Add_Args) {
    store, store_ok := read_store_file()
    defer store_destroy(&store)
    if !store_ok do os.exit(1)
    
    for other_project in store.projects {
        if strings.compare(other_project.id, args.project_id) == 0 {
            fmt.printfln("Project with id '%v' is already defined.", args.project_id)
            os.exit(1)
        }
    }
    
    store_add_project(&store, args.project_id, args.project_name)
    
    write_ok := write_store_file(store)
    if !write_ok do os.exit(1)
}

command_start :: proc(args: Start_Args) {
    store, store_ok := read_store_file()
    defer store_destroy(&store)
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

    initial_today_duration: time.Duration
    for p in store.projects {
        initial_today_duration += get_today_duration(store, p)
    }
    
    entry := store_add_entry(&store, args.project_id, time.now(), time.now())
    
    last_serialization_minute := 0
    duration_buf: [len("00:00:00")]u8
    today_duration_buf: [len("00:00:00")]u8
    
    for !got_interrupt_signal {
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
    
    fmt.println()
}

command_list :: proc() {
    store, store_ok := read_store_file()
    defer store_destroy(&store)
    if !store_ok do os.exit(1)
    
    fmt.printfln("%v registered projects:", len(store.projects))
    
    for project in store.projects {
        fmt.printfln("%v: %v", project.id, project.name)
    }
}

Summary :: struct {
    total_hours: f64,
    daily_average: f64,
    sorted_project_hours: [dynamic]f64,
    sorted_percentages: [dynamic]int,
    projects_by_hours: map[f64]string,
}

summary_destroy :: proc(summary: ^Summary) {
    delete(summary.sorted_project_hours)
    delete(summary.sorted_percentages)
    delete(summary.projects_by_hours)
    summary^ = {}
}

summary_make :: proc(args: Summary_Args, store: Store) -> Summary {
    months := []string { "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" }
    month_i := 0
    for ;month_i < len(months); month_i += 1 do if strings.compare(months[month_i], args.month) == 0 do break
    if month_i == len(months) {
        fmt.printfln("'%v' is not a known month.", args.month)
        os.exit(1)
    }
    summary_month := time.Month(month_i + 1)
    summary_year, year_ok := strconv.parse_int(args.year)
    if !year_ok || summary_year < 0 {
        fmt.printfln("Failed to parse valid year from '%v'.", args.year)
        os.exit(1)
    }
    
    project_durations: map[string]time.Duration
    defer delete(project_durations)
    
    unique_days: map[int]u8
    defer delete(unique_days)
    
    for entry in store.entries {
        entry_year, entry_month, entry_day := time.date(entry.start)
        if entry_year != summary_year || entry_month != summary_month do continue
        entry_duration := time.diff(entry.start, entry.end)
        project_duration := project_durations[entry.project_id]
        project_durations[entry.project_id] = project_duration + entry_duration
        unique_days[entry_day] = 1
    }
    
    summary: Summary
    
    for project_id, project_duration in project_durations {
        hours := time.duration_hours(project_duration)
        append(&summary.sorted_project_hours, hours)
        append(&summary.sorted_percentages, 0)
        summary.projects_by_hours[hours] = project_id
        summary.total_hours += hours
    }
    
    for &percentage, i in summary.sorted_percentages {
        hours := summary.sorted_project_hours[i]
        percentage = int(math.round(100.0 * hours / summary.total_hours))
    }
    
    sort.bubble_sort(summary.sorted_project_hours[:])
    sort.bubble_sort(summary.sorted_percentages[:])
    slice.reverse(summary.sorted_project_hours[:])
    slice.reverse(summary.sorted_percentages[:])
    
    diff := 100 - math.sum(summary.sorted_percentages[:])
    summary.sorted_percentages[0] += diff
    
    summary.daily_average = summary.total_hours / f64(len(unique_days))
    return summary
}

command_summary :: proc(args: Summary_Args) {
    store, store_ok := read_store_file()
    defer store_destroy(&store)
    if !store_ok do os.exit(1)

    summary := summary_make(args, store)
    defer summary_destroy(&summary)

    fmt.printfln("Total: %.2f hours (%.2f hours per day)", summary.total_hours, summary.daily_average)
    
    for hours, i in summary.sorted_project_hours {
        project_id := summary.projects_by_hours[hours]
        project_name: string
        for project in store.projects {
            if strings.compare(project.id, project_id) == 0 {
                project_name = project.name
            }
        }
        if project_name == {} {
            fmt.printfln("Did not find project with id '%v'.", project_id)
            os.exit(1)
        }
        
        fmt.printfln("%v: %.2f hours (%v %%)", project_name, hours, summary.sorted_percentages[i])
    }
}

command_csv :: proc(args: Csv_Args) {
    store, store_ok := read_store_file()
    defer store_destroy(&store)
    if !store_ok do os.exit(1)
    
    summary := summary_make(cast(Summary_Args)args, store)
    defer summary_destroy(&summary)
    
    for hours, i in summary.sorted_project_hours {
        project_id := summary.projects_by_hours[hours]
        project_name: string
        for project in store.projects {
            if strings.compare(project.id, project_id) == 0 {
                project_name = project.name
            }
        }
        if project_name == {} {
            fmt.printfln("Did not find project with id '%v'.", project_id)
            os.exit(1)
        }
        
        fmt.printfln("%v,%v,%v%%", args.user_name, project_name, summary.sorted_percentages[i])
    }
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

read_store_file :: proc() -> (Store, bool) {
    serialized, file_ok := os.read_entire_file(session_file_path)
    defer delete(serialized)
    if !file_ok {
        fmt.printfln("Failed to read file at '%v'.", session_file_path)
        return {}, false
    }
    return store_deserialize(transmute(string)serialized)
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

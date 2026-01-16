package trecker_gui

import "core:fmt"
import "core:strings"
import "core:time"
import "core:c"
import rl "vendor:raylib"
import tl "../trecker_lib"

Tab :: enum {
    tracker,
    graph,
}

main :: proc() {
    store, store_ok := tl.read_store_file()

    rl.SetTraceLogLevel(.WARNING)
    rl.SetConfigFlags({ .WINDOW_RESIZABLE })
    rl.SetTargetFPS(60)
    rl.InitWindow(1280, 720, "trecker")

    font := rl.LoadFontEx("RobotoCondensed-Regular.ttf", i32(get_font_size()), nil, 0)
    rl.GuiSetStyle(nil, i32(rl.GuiDefaultProperty.TEXT_SIZE), i32(get_font_size()))
    rl.GuiSetFont(font)

    current_tab: Tab
    current_entry: ^tl.Entry
    last_serialized := time.now()

    for !rl.WindowShouldClose() {
        if current_entry == nil {
            flash_window(rl.GetWindowHandle())
        } else {
            current_entry.end = time.now()
            since_serialized := time.duration_minutes(time.since(last_serialized))
            entry_duration := time.duration_minutes(time.diff(current_entry.start, current_entry.end))
            if entry_duration > 1 && since_serialized > 1 {
                tl.write_store_file(store)
                last_serialized = time.now()
            }
        }

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        {
            current_tab = draw_tab_selection(current_tab)
            switch current_tab {
                case .tracker:
                    current_entry = draw_time_tracker(&store, current_entry)
                case .graph:
            }
        }
        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}

draw_tab_selection :: proc(old_current_tab: Tab) -> (current_tab: Tab) {
    @(static) tab_names_width := f32(0)

    current_tab = old_current_tab

    padding := 10 * get_scale_factor()
    tab_x := padding
    font := rl.GuiGetFont()

    rect: rl.Rectangle
    rect.x = padding
    rect.y = padding
    rect.width = tab_names_width + padding
    rect.height = get_font_size()

    for tab in Tab {
        tab_name: cstring
        switch tab {
            case .tracker: tab_name = "Tracker"
            case .graph: tab_name = "Graph"
        }

        tab_names_width = max(tab_names_width, rl.MeasureTextEx(font, tab_name, get_font_size(), 1).x)
        rl.GuiSetState(i32(rl.GuiState.STATE_PRESSED if current_tab == tab else rl.GuiState.STATE_NORMAL))
        if rl.GuiButton(rect, tab_name) {
            current_tab = tab
        }
        rl.GuiSetState(i32(rl.GuiState.STATE_NORMAL))

        rect.x += rect.width + padding
    }

    return
}

draw_time_tracker :: proc(store: ^tl.Store, old_current_entry: ^tl.Entry) -> (current_entry: ^tl.Entry) {
    @(static) project_names_width := f32(0)
    @(static) durations_width := f32(0)
    buttons_width := 30 * get_scale_factor()

    current_entry = old_current_entry

    sorted_projects := make([dynamic]tl.Project, allocator=context.temp_allocator)

    for project in store.projects {
        append(&sorted_projects, project)
    }

    for entry in store.entries {
        index := 0
        for ;index < len(sorted_projects); index += 1 {
            if strings.equal_fold(entry.project_id, sorted_projects[index].id) {
                break
            }
        }

        project := sorted_projects[index]

        for i := index; i > 0; i -= 1 {
            sorted_projects[i] = sorted_projects[i - 1]
        }

        sorted_projects[0] = project
    }

    font := rl.GuiGetFont()

    total_duration: time.Duration
    duration_buf: [len("00:00:00")]u8

    project_name_strings := make([dynamic]cstring, allocator=context.temp_allocator)
    duration_strings := make([dynamic]cstring, allocator=context.temp_allocator)
    append(&duration_strings, "--:--:--")

    for project in sorted_projects {
        project_name := fmt.ctprintf("%v [%v]", project.name, project.id)
        append(&project_name_strings, project_name)
        project_names_width = max(project_names_width, rl.MeasureTextEx(font, project_name, get_font_size(), 1).x)

        duration := tl.get_today_duration(store^, project)
        total_duration += duration
        duration_str := fmt.ctprint(time.duration_to_string_hms(duration, duration_buf[:]))
        append(&duration_strings, duration_str)
        durations_width = max(durations_width, rl.MeasureTextEx(font, duration_str, get_font_size(), 1).x)
    }

    total_duration_str := fmt.ctprint(time.duration_to_string_hms(total_duration, duration_buf[:]))
    duration_strings[0] = total_duration_str

    padding := 10 * get_scale_factor()
    row_width := padding + project_names_width + padding + durations_width + padding + buttons_width + padding

    for i in 0..<len(sorted_projects) {
        rect := rl.Rectangle {
            x = 0,
            y = f32(3 + i) * (get_font_size() + padding) - padding / 2,
            width = row_width,
            height = get_font_size() + padding,
        }
        rl.GuiGroupBox(rect, nil)
    }

    for i in 0..<len(project_name_strings) {
        project_name := project_name_strings[i]

        rect := rl.Rectangle {
            x = padding,
            y = f32(3 + i) * (get_font_size() + padding),
            width = project_names_width,
            height = get_font_size(),
        }
        rl.GuiLabel(rect, project_name)
    }

    for i in 0..<len(duration_strings) {
        duration_str := duration_strings[i]

        rect := rl.Rectangle {
            x = padding + project_names_width + padding,
            y = f32(2 + i) * (get_font_size() + padding),
            width = durations_width,
            height = get_font_size(),
        }
        rl.GuiLabel(rect, duration_str)
    }

    for i in 0..<len(sorted_projects) {
        project := sorted_projects[i]

        rect := rl.Rectangle {
            x = padding + project_names_width + padding + durations_width + padding,
            y = f32(3 + i) * (get_font_size() + padding),
            width = buttons_width,
            height = get_font_size(),
        }

        if current_entry != nil && strings.compare(current_entry.project_id, project.id) == 0 {
            stop_icon := rl.GuiIconName.ICON_PLAYER_STOP
            if rl.GuiButton(rect, fmt.ctprintf("#%d#", stop_icon)) {
                current_entry = nil
            }
        } else {
            play_icon := rl.GuiIconName.ICON_PLAYER_PLAY
            if rl.GuiButton(rect, fmt.ctprintf("#%d#", play_icon)) {
                current_entry = tl.store_add_entry(store, project.id, time.now(), time.now())
            }
        }
    }

    return
}

get_font_size :: proc() -> f32 {
    return 24 * get_scale_factor()
}

get_scale_factor :: proc() -> f32 {
    return rl.GetWindowScaleDPI().x
}

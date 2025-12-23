package trecker_gui

import "core:fmt"
import "core:strings"
import "core:time"
import "core:c"
import rl "vendor:raylib"
import tl "../trecker_lib"

foreign import user32 "system:user32.lib"
WIN32_BOOL :: c.int;
WIN32_HWND :: rawptr
foreign user32 {
    FlashWindow :: proc "stdcall" (hWnd: WIN32_HWND, bInvert: WIN32_BOOL) -> WIN32_BOOL ---
}

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
            FlashWindow(rl.GetWindowHandle(), 0)
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
    @(static) buttons_width := f32(0)

    current_entry = old_current_entry

    padding := 10 * get_scale_factor()
    row_width := padding + project_names_width + padding + durations_width + padding + buttons_width + padding
    font := rl.GuiGetFont()
    rect: rl.Rectangle
    rect.y = padding
    rect.height = get_font_size()

    for project in store.projects {
        rect.x = padding
        
        row_background_rect := rl.Rectangle {
            y = rect.y - padding / 2,
            width = row_width,
            height = rect.height + padding,
        }
        rl.GuiGroupBox(row_background_rect, nil)

        project_name := fmt.ctprintf("%v [%v]", project.name, project.id)
        project_names_width = max(project_names_width, rl.MeasureTextEx(font, project_name, get_font_size(), 1).x)
        rect.width = project_names_width
        rl.GuiLabel(rect, project_name)
        rect.x += rect.width + padding

        duration := tl.get_today_duration(store^, project)
        duration_buf: [len("00:00:00")]u8
        duration_str := fmt.ctprint(time.duration_to_string_hms(duration, duration_buf[:]))
        durations_width = max(durations_width, rl.MeasureTextEx(font, duration_str, get_font_size(), 1).x)
        rect.width = durations_width
        rl.GuiLabel(rect, duration_str)
        rect.x += rect.width + padding

        buttons_width = max(buttons_width, 30 * get_scale_factor())
        rect.width = buttons_width
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

        rect.y += rect.height + padding
    }

    return
}

get_font_size :: proc() -> f32 {
    return 24 * get_scale_factor()
}

get_scale_factor :: proc() -> f32 {
    return rl.GetWindowScaleDPI().x
}

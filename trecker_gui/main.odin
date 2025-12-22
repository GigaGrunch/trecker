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

main :: proc() {
    store, store_ok := tl.read_store_file()

    rl.SetTraceLogLevel(.WARNING)
    rl.SetConfigFlags({ .WINDOW_RESIZABLE })
    rl.SetTargetFPS(60)
    rl.InitWindow(1280, 720, "trecker")

    scale_factor := rl.GetWindowScaleDPI().x
    font_size := 24 * scale_factor
    font := rl.LoadFontEx("RobotoCondensed-Regular.ttf", i32(font_size), nil, 0)
    rl.GuiSetStyle(nil, i32(rl.GuiDefaultProperty.TEXT_SIZE), i32(font_size))
    rl.GuiSetFont(font)

    scroll_value := f32(0)
    scroll_content_size := rl.Vector2 { 1, 1 }
    project_names_width := f32(0)
    durations_width := f32(0)
    current_entry: ^tl.Entry
    last_serialized := time.now()

    for !rl.WindowShouldClose() {
        if current_entry == nil {
            FlashWindow(rl.GetWindowHandle(), 0)
        } else {
            current_entry.end = time.now()
            if time.duration_minutes(time.since(last_serialized)) > 1 {
                tl.write_store_file(store)
                last_serialized = time.now()
            }
        }

        scroll_render_target := rl.LoadRenderTexture(i32(scroll_content_size.x), i32(scroll_content_size.y))
        defer rl.UnloadRenderTexture(scroll_render_target)

        scroll_value += rl.GetMouseWheelMove() * 20
        scroll_value = clamp(scroll_value, f32(rl.GetScreenHeight()) - scroll_content_size.y, 0)
        scroll_content_size.x = f32(rl.GetScreenWidth())
        scroll_content_size.y = 1

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        {
            rl.BeginTextureMode(scroll_render_target)
            rl.ClearBackground(rl.BLACK)
            {
                padding := 10 * scale_factor
                project_y := padding

                for project in store.projects {
                    rect: rl.Rectangle
                    rect.x = padding
                    rect.y = project_y
                    rect.height = font_size

                    row_background_rect := rl.Rectangle {
                        y = rect.y - padding / 2,
                        width = scroll_content_size.x,
                        height = rect.height + padding,
                    }
                    rl.GuiGroupBox(row_background_rect, nil)

                    project_name := fmt.ctprintf("%v [%v]", project.name, project.id)
                    project_names_width = max(project_names_width, rl.MeasureTextEx(font, project_name, font_size, 1).x)
                    rect.width = project_names_width
                    rl.GuiLabel(rect, project_name)
                    rect.x += rect.width + padding

                    duration := tl.get_today_duration(store, project)
                    duration_buf: [len("00:00:00")]u8
                    duration_str := fmt.ctprint(time.duration_to_string_hms(duration, duration_buf[:]))
                    durations_width = max(durations_width, rl.MeasureTextEx(font, duration_str, font_size, 1).x)
                    rect.width = durations_width
                    rl.GuiLabel(rect, duration_str)
                    rect.x += rect.width + padding

                    rect.width = 30 * scale_factor
                    if current_entry != nil && strings.compare(current_entry.project_id, project.id) == 0 {
                        stop_icon := rl.GuiIconName.ICON_PLAYER_STOP
                        if rl.GuiButton(rect, fmt.ctprintf("#%d#", stop_icon)) {
                            current_entry = nil
                        }
                    } else {
                        play_icon := rl.GuiIconName.ICON_PLAYER_PLAY
                        if rl.GuiButton(rect, fmt.ctprintf("#%d#", play_icon)) {
                            current_entry = tl.store_add_entry(&store, project.id, time.now(), time.now())
                        }
                    }

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
    }
}


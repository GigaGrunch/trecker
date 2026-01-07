package trecker_gui

import "core:c"

foreign import user32 "system:user32.lib"

WIN32_BOOL :: c.int;
WIN32_HWND :: rawptr

foreign user32 {
    FlashWindow :: proc "stdcall" (hWnd: WIN32_HWND, bInvert: WIN32_BOOL) -> WIN32_BOOL ---
}

flash_window :: proc(window_handle: rawptr) {
	FlashWindow(window_handle, 0)
}

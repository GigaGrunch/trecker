package trecker_gui

import "core:fmt"

flash_window :: proc(window_handle: rawptr) {
	@(static) warning_printed := false
	if !warning_printed {
		fmt.println("WARNING: flash_window not implemented for OS", ODIN_OS)
		warning_printed = true
	}
}

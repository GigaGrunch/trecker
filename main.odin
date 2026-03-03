package trecker

import "core:os"
import "core:fmt"

main :: proc() {
	if !string_lookup_init() do os.exit(1)
}

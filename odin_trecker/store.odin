package trecker

import "core:strings"

store_version :: 2

Store :: struct {

}

serialize_store :: proc(store: Store) -> []u8 {
    builder := strings.builder_make()
    strings.write_string(&builder, "version: ")
    strings.write_int(&builder, store_version)
    strings.write_rune(&builder, '\n')
    return builder.buf[:]
}

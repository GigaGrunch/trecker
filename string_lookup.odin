package trecker

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:mem/virtual"
import "core:testing"

string_allocator: mem.Allocator
string_lookup: [dynamic]cstring
string_index_lookup: map[string]int

string_lookup_init :: proc() -> (ok := false) {
	string_arena: virtual.Arena
	err := virtual.arena_init_growing(&string_arena)
	if err != {} {
		fmt.printfln("Failed to initialize string arena: %v", err)
	} else {
		string_allocator = virtual.arena_allocator(&string_arena)
		ok = true
	}
	return
}

string_get_stable :: proc(str: string) -> string {
	return string(cstring_get_stable(str))
}

cstring_get_stable :: proc(str: string) -> cstring {
	if str not_in string_index_lookup {
		dupe := strings.clone_to_cstring(str, string_allocator)
		string_index_lookup[string(dupe)] = len(string_lookup)
		append(&string_lookup, dupe)
	}

	assert(str in string_index_lookup)
	string_index := string_index_lookup[str]
	return string_lookup[string_index]
}

@test
test_string_lookup :: proc(t: ^testing.T) {
	string_allocator = context.temp_allocator
	defer {
		free_all(context.temp_allocator)
		delete(string_lookup)
		delete(string_index_lookup)
		string_allocator = {}
	}

	test_buffer := make([]u8, 10)
	defer delete(test_buffer)

	test_1_original := "test1"
	mem.copy(raw_data(test_buffer), raw_data(test_1_original), len(test_1_original))
	test_1_ptr := transmute(string)(test_buffer[:len(test_1_original)])
	test_1_original_result := string_get_stable(test_1_original)
	test_1_ptr_result := string_get_stable(test_1_ptr)

	test_2_original := "test2"
	mem.zero(raw_data(test_buffer), len(test_buffer))
	mem.copy(raw_data(test_buffer), raw_data(test_2_original), len(test_2_original))
	test_2_ptr := transmute(string)(test_buffer[:len(test_2_original)])
	test_2_original_result := string_get_stable(test_2_original)
	test_2_ptr_result := string_get_stable(test_2_ptr)

	testing.expect(t, raw_data(test_1_original_result) == raw_data(test_1_ptr_result))
	testing.expect(t, raw_data(test_1_original_result) != raw_data(test_1_original))
	testing.expect(t, strings.compare(test_1_original_result, test_1_original) == 0)
	
	testing.expect(t, raw_data(test_2_original_result) == raw_data(test_2_ptr_result))
	testing.expect(t, raw_data(test_2_original_result) != raw_data(test_2_original))
	testing.expect(t, strings.compare(test_2_original_result, test_2_original) == 0)
}

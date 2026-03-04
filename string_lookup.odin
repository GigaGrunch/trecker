package trecker

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:mem/virtual"
import "core:testing"

string_arena: virtual.Arena
string_lookup: [dynamic]cstring
string_index_lookup: map[string]int

string_lookup_init :: proc() -> mem.Allocator_Error {
	return virtual.arena_init_growing(&string_arena)
}

stable_string :: proc(str: string) -> string {
	return string(stable_cstring(str))
}

stable_cstring :: proc(str: string) -> cstring {
	if str not_in string_index_lookup {
		allocator := virtual.arena_allocator(&string_arena)
		dupe := strings.clone_to_cstring(str, allocator)
		string_index_lookup[string(dupe)] = len(string_lookup)
		append(&string_lookup, dupe)
	}

	assert(str in string_index_lookup)
	string_index := string_index_lookup[str]
	return string_lookup[string_index]
}

@test
test_string_lookup :: proc(t: ^testing.T) {
	init_err := string_lookup_init()
	testing.expect(t, init_err == .None)

	defer {
		virtual.arena_destroy(&string_arena)
		delete(string_lookup)
		delete(string_index_lookup)
	}

	test_buffer := make([]u8, 10)
	defer delete(test_buffer)

	test_1_original := "test1"
	mem.copy(raw_data(test_buffer), raw_data(test_1_original), len(test_1_original))
	test_1_ptr := transmute(string)(test_buffer[:len(test_1_original)])
	test_1_original_result := stable_string(test_1_original)
	test_1_ptr_result := stable_string(test_1_ptr)

	test_2_original := "test2"
	mem.zero(raw_data(test_buffer), len(test_buffer))
	mem.copy(raw_data(test_buffer), raw_data(test_2_original), len(test_2_original))
	test_2_ptr := transmute(string)(test_buffer[:len(test_2_original)])
	test_2_original_result := stable_string(test_2_original)
	test_2_ptr_result := stable_string(test_2_ptr)

	testing.expect(t, raw_data(test_1_original_result) == raw_data(test_1_ptr_result))
	testing.expect(t, raw_data(test_1_original_result) != raw_data(test_1_original))
	testing.expect(t, strings.compare(test_1_original_result, test_1_original) == 0)
	
	testing.expect(t, raw_data(test_2_original_result) == raw_data(test_2_ptr_result))
	testing.expect(t, raw_data(test_2_original_result) != raw_data(test_2_original))
	testing.expect(t, strings.compare(test_2_original_result, test_2_original) == 0)
}

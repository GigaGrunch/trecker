package trecker

import "core:strings"

Tokenizer :: struct {
    data: []u8,
    split_chars: []u8,
    current: int,
    token_index: int,
}

tokenize :: proc{tokenize_bytes, tokenize_string}

tokenize_string :: proc(data: string, split_chars: string) -> Tokenizer {
    return Tokenizer {
        data = transmute([]u8)data,
        split_chars = transmute([]u8)split_chars,
    }
}

tokenize_bytes :: proc(data: []u8, split_chars: string) -> Tokenizer {
    return Tokenizer {
        data = data,
        split_chars = transmute([]u8)split_chars,
    }
}

next_token :: proc(it: ^Tokenizer) -> (string, bool) {
    token, _, ok := next_token_indexed(it)
    return token, ok
}

next_token_indexed :: proc(it: ^Tokenizer) -> (string, int, bool) {
    at_split_char :: proc(it: ^Tokenizer) -> bool {
        for char in it.split_chars {
            if char == it.data[it.current] do return true
        }
        return false
    }
    
    for it.current < len(it.data) {
        if at_split_char(it) do it.current += 1
        else do break
    }
    
    if it.current == len(it.data) do return "", 0, false
    start := it.current
    
    for it.current < len(it.data) {
        if at_split_char(it) do break
        else do it.current += 1
    }
    
    result := it.data[start:it.current]
    result_str := transmute(string)result
    trimmed_result := strings.trim_space(result_str)
    
    defer it.token_index += 1
    return trimmed_result, it.token_index, true
}

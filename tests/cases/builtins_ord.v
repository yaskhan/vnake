module main

const char_str = 'A'

// To compile with globals, use: v -enable-globals .
__global val Any

fn init() {
unsafe { val = char_str[0].u32() }
}
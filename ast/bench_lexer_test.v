module ast

import time

fn test_lexer_speed() {
	source := 'def foo(x: int) -> int:\n    return x + 123 * 456.789\n' .repeat(10000)
	// Warmup
	mut l1 := new_lexer(source, 'test.py')
	for {
		tok := l1.next_token()
		if tok.typ == .eof { break }
	}

	sw := time.new_stopwatch()
	mut l := new_lexer(source, 'test.py')
	mut count := 0
	for {
		tok := l.next_token()
		count++
		if tok.typ == .eof { break }
	}
	println('\nLexing ${count} tokens took ${sw.elapsed().microseconds()}us')
}

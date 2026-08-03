module ast

import time

fn test_lexer_speed() {
	// Verify get_keyword correctness
	assert get_keyword('def') or { '' } == 'def'
	assert get_keyword('class') or { '' } == 'class'
	assert get_keyword('return') or { '' } == 'return'
	assert get_keyword('not_a_keyword') == none
	assert get_keyword('de') == none
	assert get_keyword('def_not') == none

	// Verify Lexer tokenizes identifiers and keywords properly
	source_test := 'def my_func(x):\n    return x\n'
	mut l_test := new_lexer(source_test, 'test.py')

	tok1 := l_test.next_token()
	assert tok1.typ == .keyword
	assert tok1.value == 'def'

	tok2 := l_test.next_token()
	assert tok2.typ == .identifier
	assert tok2.value == 'my_func'

	tok3 := l_test.next_token()
	assert tok3.typ == .lparen

	tok4 := l_test.next_token()
	assert tok4.typ == .identifier
	assert tok4.value == 'x'

	tok5 := l_test.next_token()
	assert tok5.typ == .rparen

	tok6 := l_test.next_token()
	assert tok6.typ == .colon

	tok7 := l_test.next_token()
	assert tok7.typ == .newline

	tok8 := l_test.next_token()
	assert tok8.typ == .indent

	tok9 := l_test.next_token()
	assert tok9.typ == .keyword
	assert tok9.value == 'return'

	tok10 := l_test.next_token()
	assert tok10.typ == .identifier
	assert tok10.value == 'x'

	println('Lexer correctness checks passed successfully!')

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

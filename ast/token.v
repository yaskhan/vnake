module ast

// ==================== TOKEN TYPES ====================

pub enum TokenType {
	eof
	newline
	indent
	dedent
	identifier
	number
	string_tok
	keyword
	operator
	lparen
	rparen
	lbracket
	rbracket
	lbrace
	rbrace
	colon
	comma
	dot
	semicolon
	at
	arrow
	walrus
	ellipsis
	fstring_tok
	tstring_tok
}

// ==================== TOKEN ====================

pub struct Token {
pub:
	typ      TokenType
	value    string
	line     int
	column   int
	filename string
}

fn (t Token) str() string {
	return 'Token(${t.typ}, ${t.value.str()}, ${t.line}:${t.column})'
}

fn (t Token) is_keyword(kw string) bool {
	return t.typ == .keyword && t.value == kw
}

fn (t Token) is_op(op string) bool {
	return t.typ == .operator && t.value == op
}

// Python keywords
const keywords = [
	'False',
	'None',
	'True',
	'and',
	'as',
	'assert',
	'async',
	'await',
	'break',
	'class',
	'continue',
	'def',
	'del',
	'elif',
	'else',
	'except',
	'finally',
	'for',
	'from',
	'global',
	'if',
	'import',
	'in',
	'is',
	'lambda',
	'nonlocal',
	'not',
	'or',
	'pass',
	'raise',
	'return',
	'try',
	'while',
	'with',
	'yield',
]

// get_keyword returns the static string literal for a Python keyword, or none if s is not a keyword.
// ⚡ Bolt: Delegating to get_keyword_slice avoids code duplication while preserving the public API.
pub fn get_keyword(s string) ?string {
	return get_keyword_slice(s, 0, s.len)
}

// is_keyword checks if the string is a Python keyword.
// ⚡ Bolt: Optimized string set membership check using two-stage dispatch via get_keyword.
fn is_keyword(s string) bool {
	if _ := get_keyword(s) {
		return true
	}
	return false
}

// get_keyword_slice maps a slice of the source string directly to a static keyword literal.
// This allows lexing keywords with zero heap allocations or string slicing.
// ⚡ Bolt: Using two-stage dispatch matching the first character and length for O(1) matching.
pub fn get_keyword_slice(s string, start int, len int) ?string {
	if len < 2 || len > 8 {
		return none
	}
	ch := s[start]
	match ch {
		`a` {
			match len {
				2 { if s[start + 1] == `s` { return 'as' } }
				3 { if s[start + 1] == `n` && s[start + 2] == `d` { return 'and' } }
				5 {
					if s[start + 1] == `s` && s[start + 2] == `y` && s[start + 3] == `n` && s[start + 4] == `c` { return 'async' }
					if s[start + 1] == `w` && s[start + 2] == `a` && s[start + 3] == `i` && s[start + 4] == `t` { return 'await' }
				}
				6 { if s[start + 1] == `s` && s[start + 2] == `s` && s[start + 3] == `e` && s[start + 4] == `r` && s[start + 5] == `t` { return 'assert' } }
				else {}
			}
		}
		`b` {
			if len == 5 && s[start + 1] == `r` && s[start + 2] == `e` && s[start + 3] == `a` && s[start + 4] == `k` { return 'break' }
		}
		`c` {
			match len {
				5 { if s[start + 1] == `l` && s[start + 2] == `a` && s[start + 3] == `s` && s[start + 4] == `s` { return 'class' } }
				8 { if s[start + 1] == `o` && s[start + 2] == `n` && s[start + 3] == `t` && s[start + 4] == `i` && s[start + 5] == `n` && s[start + 6] == `u` && s[start + 7] == `e` { return 'continue' } }
				else {}
			}
		}
		`d` {
			if len == 3 {
				if s[start + 1] == `e` {
					if s[start + 2] == `f` { return 'def' }
					if s[start + 2] == `l` { return 'del' }
				}
			}
		}
		`e` {
			match len {
				4 {
					if s[start + 1] == `l` {
						if s[start + 2] == `i` && s[start + 3] == `f` { return 'elif' }
						if s[start + 2] == `s` && s[start + 3] == `e` { return 'else' }
					}
				}
				6 { if s[start + 1] == `x` && s[start + 2] == `c` && s[start + 3] == `e` && s[start + 4] == `p` && s[start + 5] == `t` { return 'except' } }
				else {}
			}
		}
		`f` {
			match len {
				3 { if s[start + 1] == `o` && s[start + 2] == `r` { return 'for' } }
				4 { if s[start + 1] == `r` && s[start + 2] == `o` && s[start + 3] == `m` { return 'from' } }
				7 { if s[start + 1] == `i` && s[start + 2] == `n` && s[start + 3] == `a` && s[start + 4] == `l` && s[start + 5] == `l` && s[start + 6] == `y` { return 'finally' } }
				else {}
			}
		}
		`F` {
			if len == 5 && s[start + 1] == `a` && s[start + 2] == `l` && s[start + 3] == `s` && s[start + 4] == `e` { return 'False' }
		}
		`g` {
			if len == 6 && s[start + 1] == `l` && s[start + 2] == `o` && s[start + 3] == `b` && s[start + 4] == `a` && s[start + 5] == `l` { return 'global' }
		}
		`i` {
			match len {
				2 {
					if s[start + 1] == `f` { return 'if' }
					if s[start + 1] == `n` { return 'in' }
					if s[start + 1] == `s` { return 'is' }
				}
				6 { if s[start + 1] == `m` && s[start + 2] == `p` && s[start + 3] == `o` && s[start + 4] == `r` && s[start + 5] == `t` { return 'import' } }
				else {}
			}
		}
		`l` {
			if len == 6 && s[start + 1] == `a` && s[start + 2] == `m` && s[start + 3] == `b` && s[start + 4] == `d` && s[start + 5] == `a` { return 'lambda' }
		}
		`n` {
			match len {
				3 { if s[start + 1] == `o` && s[start + 2] == `t` { return 'not' } }
				8 { if s[start + 1] == `o` && s[start + 2] == `n` && s[start + 3] == `l` && s[start + 4] == `o` && s[start + 5] == `c` && s[start + 6] == `a` && s[start + 7] == `l` { return 'nonlocal' } }
				else {}
			}
		}
		`N` {
			if len == 4 && s[start + 1] == `o` && s[start + 2] == `n` && s[start + 3] == `e` { return 'None' }
		}
		`o` {
			if len == 2 && s[start + 1] == `r` { return 'or' }
		}
		`p` {
			if len == 4 && s[start + 1] == `a` && s[start + 2] == `s` && s[start + 3] == `s` { return 'pass' }
		}
		`r` {
			match len {
				5 { if s[start + 1] == `a` && s[start + 2] == `i` && s[start + 3] == `s` && s[start + 4] == `e` { return 'raise' } }
				6 { if s[start + 1] == `e` && s[start + 2] == `t` && s[start + 3] == `u` && s[start + 4] == `r` && s[start + 5] == `n` { return 'return' } }
				else {}
			}
		}
		`t` {
			if len == 3 && s[start + 1] == `r` && s[start + 2] == `y` { return 'try' }
		}
		`T` {
			if len == 4 && s[start + 1] == `r` && s[start + 2] == `u` && s[start + 3] == `e` { return 'True' }
		}
		`w` {
			match len {
				4 { if s[start + 1] == `i` && s[start + 2] == `t` && s[start + 3] == `h` { return 'with' } }
				5 { if s[start + 1] == `h` && s[start + 2] == `i` && s[start + 3] == `l` && s[start + 4] == `e` { return 'while' } }
				else {}
			}
		}
		`y` {
			if len == 5 && s[start + 1] == `i` && s[start + 2] == `e` && s[start + 3] == `l` && s[start + 4] == `d` { return 'yield' }
		}
		else {}
	}
	return none
}

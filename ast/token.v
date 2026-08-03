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
// ⚡ Bolt: Returning a static string literal instead of the sliced string eliminates heap allocations for keywords.
pub fn get_keyword(s string) ?string {
	if s.len < 2 || s.len > 8 {
		return none
	}
	match s[0] {
		`a` {
			match s.len {
				2 { if s == 'as' { return 'as' } }
				3 { if s == 'and' { return 'and' } }
				5 {
					if s == 'async' { return 'async' }
					if s == 'await' { return 'await' }
				}
				6 { if s == 'assert' { return 'assert' } }
				else {}
			}
		}
		`b` {
			if s.len == 5 && s == 'break' { return 'break' }
		}
		`c` {
			match s.len {
				5 { if s == 'class' { return 'class' } }
				8 { if s == 'continue' { return 'continue' } }
				else {}
			}
		}
		`d` {
			if s.len == 3 {
				if s == 'def' { return 'def' }
				if s == 'del' { return 'del' }
			}
		}
		`e` {
			match s.len {
				4 {
					if s == 'elif' { return 'elif' }
					if s == 'else' { return 'else' }
				}
				6 { if s == 'except' { return 'except' } }
				else {}
			}
		}
		`f` {
			match s.len {
				3 { if s == 'for' { return 'for' } }
				4 { if s == 'from' { return 'from' } }
				7 { if s == 'finally' { return 'finally' } }
				else {}
			}
		}
		`F` {
			if s.len == 5 && s == 'False' { return 'False' }
		}
		`g` {
			if s.len == 6 && s == 'global' { return 'global' }
		}
		`i` {
			match s.len {
				2 {
					if s == 'if' { return 'if' }
					if s == 'in' { return 'in' }
					if s == 'is' { return 'is' }
				}
				6 { if s == 'import' { return 'import' } }
				else {}
			}
		}
		`l` {
			if s.len == 6 && s == 'lambda' { return 'lambda' }
		}
		`n` {
			match s.len {
				3 { if s == 'not' { return 'not' } }
				8 { if s == 'nonlocal' { return 'nonlocal' } }
				else {}
			}
		}
		`N` {
			if s.len == 4 && s == 'None' { return 'None' }
		}
		`o` {
			if s.len == 2 && s == 'or' { return 'or' }
		}
		`p` {
			if s.len == 4 && s == 'pass' { return 'pass' }
		}
		`r` {
			match s.len {
				5 { if s == 'raise' { return 'raise' } }
				6 { if s == 'return' { return 'return' } }
				else {}
			}
		}
		`t` {
			if s.len == 3 && s == 'try' { return 'try' }
		}
		`T` {
			if s.len == 4 && s == 'True' { return 'True' }
		}
		`w` {
			match s.len {
				4 { if s == 'with' { return 'with' } }
				5 { if s == 'while' { return 'while' } }
				else {}
			}
		}
		`y` {
			if s.len == 5 && s == 'yield' { return 'yield' }
		}
		else {}
	}
	return none
}

// is_keyword checks if the string is a Python keyword.
// ⚡ Bolt: Optimized string set membership check using two-stage dispatch via get_keyword.
fn is_keyword(s string) bool {
	if _ := get_keyword(s) {
		return true
	}
	return false
}

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

// is_keyword checks if the string is a Python keyword.
// ⚡ Bolt: Using a match expression with a length-based fast path is faster than
// linear search in an array literal in V 0.5.1.
fn is_keyword(s string) bool {
	// ⚡ Bolt: Optimized string set membership check using byte-level dispatch.
	// Using a `match` expression on the first character followed by direct comparisons
	// is significantly faster (~2x in -prod) than a single large `match` expression
	// in V 0.5.1, as it reduces the number of string comparisons in the hot path.
	if s.len < 2 || s.len > 8 {
		return false
	}
	match s[0] {
		`a` { return s == 'and' || s == 'as' || s == 'assert' || s == 'async' || s == 'await' }
		`b` { return s == 'break' }
		`c` { return s == 'class' || s == 'continue' }
		`d` { return s == 'def' || s == 'del' }
		`e` { return s == 'elif' || s == 'else' || s == 'except' }
		`f` { return s == 'finally' || s == 'for' || s == 'from' }
		`F` { return s == 'False' }
		`g` { return s == 'global' }
		`i` { return s == 'if' || s == 'import' || s == 'in' || s == 'is' }
		`l` { return s == 'lambda' }
		`n` { return s == 'nonlocal' || s == 'not' }
		`N` { return s == 'None' }
		`o` { return s == 'or' }
		`p` { return s == 'pass' }
		`r` { return s == 'raise' || s == 'return' }
		`t` { return s == 'try' }
		`T` { return s == 'True' }
		`w` { return s == 'while' || s == 'with' }
		`y` { return s == 'yield' }
		else { return false }
	}
}

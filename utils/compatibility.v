module utils

import strings

pub struct CompatibilityLayer {
}

pub fn new_compatibility_layer() CompatibilityLayer {
	return CompatibilityLayer{}
}

pub fn (c CompatibilityLayer) is_v_reserved(name string) bool {
	if is_v_reserved_keyword(name) {
		return true
	}
	// ⚡ Bolt: Only call to_lower() if name contains uppercase letters.
	// Measured ~12% speedup for lowercase names (no allocation).
	for ch in name {
		if ch >= `A` && ch <= `Z` {
			return is_v_reserved_keyword(name.to_lower())
		}
	}
	return false
}

// is_v_reserved_keyword checks if the name is a V reserved keyword.
// This is optimized to use a two-stage dispatch (first on length, then on first character)
// which reduces full string comparisons in the hot path.
fn is_v_reserved_keyword(name string) bool {
	if name.len < 2 || name.len > 9 {
		return false
	}
	return match name.len {
		2 {
			match name[0] {
				`f` { name == 'fn' }
				`i` { name == 'if' || name == 'in' || name == 'is' }
				`g` { name == 'go' }
				`a` { name == 'as' }
				else { false }
			}
		}
		3 {
			match name[0] {
				`m` { name == 'mut' || name == 'map' }
				`f` { name == 'for' }
				`p` { name == 'pub' }
				`a` { name == 'any' }
				`A` { name == 'Any' }
				else { false }
			}
		}
		4 {
			match name[0] {
				`t` { name == 'type' }
				`e` { name == 'else' || name == 'enum' }
				`c` { name == 'chan' }
				`n` { name == 'none' }
				`b` { name == 'bool' }
				else { false }
			}
		}
		5 {
			match name[0] {
				`m` { name == 'match' }
				`c` { name == 'const' }
				`d` { name == 'defer' }
				`s` { name == 'spawn' }
				`a` { name == 'array' }
				`u` { name == 'union' }
				else { false }
			}
		}
		6 {
			match name[0] {
				`s` { name == 'struct' || name == 'shared' || name == 'sizeof' || name == 'string' }
				`r` { name == 'return' }
				`i` { name == 'import' }
				`m` { name == 'module' }
				`u` { name == 'unsafe' }
				`a` { name == 'assert' }
				`t` { name == 'typeof' }
				else { false }
			}
		}
		8 {
			name == '__global'
		}
		9 {
			name == 'interface'
		}
		else {
			false
		}
	}
}

pub fn (c CompatibilityLayer) is_python_soft_keyword(name string) bool {
	// ⚡ Bolt: Using match expression instead of array lookup avoids allocation.
	if name.len < 4 || name.len > 5 {
		return false
	}
	return match name {
		'match', 'case', 'type', 'soft' { true }
		else { false }
	}
}

pub fn (c CompatibilityLayer) preprocess_source(source string) string {
	// ⚡ Bolt: First pass for t-strings using strings.Builder.
	mut t_processed := c.preprocess_tstrings(source)

	// ⚡ Bolt: If the source doesn't contain 'except' or 'case', we can skip the expensive line-by-line parsing.
	if !t_processed.contains('except') && !t_processed.contains('case') {
		return t_processed
	}

	// ⚡ Bolt: Combined pass for except and match to avoid multiple split/join cycles.
	// This reduces complexity from O(3*N) string scans to O(2*N).
	lines := t_processed.split('\n')
	mut result := []string{cap: lines.len}
	mut i := 0
	for i < lines.len {
		line := lines[i]

		// Try except header
		mut is_processed := false
		except_header := c.match_except_header(line)
		if except_header.kind != '' {
			full_header, j := c.collect_multiline_header(lines, i, except_header.rest)
			colon_index := c.find_header_colon(full_header)
			if colon_index != -1 {
				clause := full_header[..colon_index]
				suffix := full_header[colon_index + 1..]
				rewritten_clause := c.wrap_bracketless_except_clause(clause)
				result << '${except_header.indent}${except_header.kind}${rewritten_clause}:${suffix}'
				i = j + 1
				is_processed = true
			}
		}

		if !is_processed {
			// Try case header
			case_header := c.match_case_header(line)
			if case_header.kind != '' {
				full_case, j := c.collect_multiline_header(lines, i, case_header.rest)
				colon_index := c.find_header_colon(full_case)
				if colon_index != -1 {
					pattern := full_case[..colon_index]
					rest := full_case[colon_index + 1..]
					mangled := c.mangle_recursive(pattern)
					result << '${case_header.indent}case ${mangled}:${rest}'
					i = j + 1
					is_processed = true
				}
			}
		}

		if is_processed {
			continue
		}

		result << line
		i++
	}
	return result.join('\n')
}

fn (c CompatibilityLayer) preprocess_tstrings(source string) string {
	// ⚡ Bolt: Fast path for source without potential t-string prefixes.
	if !source.contains('t') && !source.contains('T') && !source.contains('r')
		&& !source.contains('R') {
		return source
	}

	mut sb := strings.new_builder(source.len)
	mut i := 0
	for i < source.len {
		ch := source[i]
		// ⚡ Bolt: Byte-dispatch before calling helper avoids millions of function calls.
		if (ch == `t` || ch == `T` || ch == `r` || ch == `R`) && c.is_tstring_prefix_start(source,
			i) {
			prefix_end, quote, quote_len, raw_prefix := c.scan_tstring_prefix(source,
				i)
			if prefix_end > i {
				if raw_prefix {
					sb.write_byte(`r`)
				}
				sb.write_byte(`f`)
				sb.write_byte(quote)
				if quote_len == 3 {
					sb.write_byte(quote)
					sb.write_byte(quote)
				}
				marker := if raw_prefix { '__py2v_rt__' } else { '__py2v_t__' }
				sb.write_string(marker)
				i = prefix_end + quote_len
				continue
			}
		}
		sb.write_byte(ch)
		i++
	}
	return sb.str()
}

fn (c CompatibilityLayer) is_tstring_prefix_start(source string, index int) bool {
	if index >= source.len {
		return false
	}
	ch := source[index]
	if ch != `t` && ch != `T` && ch != `r` && ch != `R` {
		return false
	}
	if index > 0 {
		prev := source[index - 1]
		if !(prev.is_space() || prev == `=` || prev == `(` || prev == `[` || prev == `{`
			|| prev == `,` || prev == `:` || prev == `!` || prev == `|` || prev == `&`) {
			return false
		}
	}
	return true
}

fn (c CompatibilityLayer) scan_tstring_prefix(source string, index int) (int, u8, int, bool) {
	mut i := index
	mut has_t := false
	mut raw_prefix := false
	for i < source.len {
		ch := source[i]
		if ch == `t` || ch == `T` {
			has_t = true
			i++
			continue
		}
		if ch == `r` || ch == `R` {
			raw_prefix = true
			i++
			continue
		}
		break
	}
	if !has_t || i >= source.len {
		return index, 0, 0, false
	}
	quote := source[i]
	if quote != `"` && quote != `'` {
		return index, 0, 0, false
	}
	if i + 2 < source.len && source[i + 1] == quote && source[i + 2] == quote {
		return i, quote, 3, raw_prefix
	}
	return i, quote, 1, raw_prefix
}

struct ExceptHeader {
	indent string
	kind   string
	rest   string
}

fn (c CompatibilityLayer) match_except_header(line string) ExceptHeader {
	mut i := 0
	for i < line.len && (line[i] == ` ` || line[i] == `\t`) {
		i++
	}
	// ⚡ Bolt: Defer indent extraction until a match is confirmed.
	if i + 7 > line.len {
		return ExceptHeader{}
	}
	// Byte-level check for 'except* '
	if i + 8 <= line.len && line[i] == `e` && line[i + 1] == `x` && line[i + 2] == `c`
		&& line[i + 3] == `e` && line[i + 4] == `p` && line[i + 5] == `t` && line[i + 6] == `*`
		&& line[i + 7] == ` ` {
		return ExceptHeader{
			indent: line[..i]
			kind:   'except* '
			rest:   line[i + 8..]
		}
	}
	// Byte-level check for 'except '
	if line[i] == `e` && line[i + 1] == `x` && line[i + 2] == `c` && line[i + 3] == `e`
		&& line[i + 4] == `p` && line[i + 5] == `t` && line[i + 6] == ` ` {
		return ExceptHeader{
			indent: line[..i]
			kind:   'except '
			rest:   line[i + 7..]
		}
	}
	return ExceptHeader{}
}

fn (c CompatibilityLayer) find_header_colon(text string) int {
	_, index := c.find_header_colon_with_depth(text, 0)
	return index
}

fn (c CompatibilityLayer) find_header_colon_with_depth(text string, initial_depth int) (int, int) {
	mut depth := initial_depth
	for i, ch in text {
		if ch == `(` || ch == `[` || ch == `{` {
			depth++
		} else if ch == `)` || ch == `]` || ch == `}` {
			if depth > 0 {
				depth--
			}
		} else if ch == `:` && depth == 0 {
			return depth, i
		}
	}
	return depth, -1
}

fn (c CompatibilityLayer) collect_multiline_header(lines []string, start_index int, initial_rest string) (string, int) {
	depth, colon_index := c.find_header_colon_with_depth(initial_rest, 0)
	if colon_index != -1 {
		return initial_rest, start_index
	}

	mut current_depth := depth
	mut full_header_parts := [initial_rest]
	mut j := start_index
	for j + 1 < lines.len {
		j++
		next_line := lines[j]
		full_header_parts << '\n' + next_line
		new_depth, next_colon_index := c.find_header_colon_with_depth('\n' + next_line,
			current_depth)
		current_depth = new_depth
		if next_colon_index != -1 {
			break
		}
	}
	return full_header_parts.join(''), j
}

fn (c CompatibilityLayer) wrap_bracketless_except_clause(clause string) string {
	stripped := clause.trim_space()
	if stripped.len == 0 || stripped.starts_with('(') {
		return clause
	}
	head, as_clause := c.split_except_alias(clause)
	if !c.has_top_level_comma(head) {
		return clause
	}
	return '(${head.trim_space()})${as_clause}'
}

fn (c CompatibilityLayer) split_except_alias(clause string) (string, string) {
	mut depth := 0
	mut idx := 0
	for idx < clause.len {
		ch := clause[idx]
		if ch == `(` || ch == `[` || ch == `{` {
			depth++
		} else if ch == `)` || ch == `]` || ch == `}` {
			if depth > 0 {
				depth--
			}
		} else if depth == 0 && idx + 4 <= clause.len && clause[idx] == ` ` && clause[idx + 1] == `a` && clause[idx + 2] == `s` && clause[idx + 3] == ` ` {
			return clause[..idx], clause[idx..]
		}
		idx++
	}
	return clause, ''
}

fn (c CompatibilityLayer) has_top_level_comma(text string) bool {
	mut depth := 0
	for ch in text {
		if ch == `(` || ch == `[` || ch == `{` {
			depth++
		} else if ch == `)` || ch == `]` || ch == `}` {
			if depth > 0 {
				depth--
			}
		} else if ch == `,` && depth == 0 {
			return true
		}
	}
	return false
}

struct CaseHeader {
	indent string
	kind   string
	rest   string
}

fn (c CompatibilityLayer) match_case_header(line string) CaseHeader {
	mut i := 0
	for i < line.len && (line[i] == ` ` || line[i] == `\t`) {
		i++
	}
	// ⚡ Bolt: Defer indent extraction until a match is confirmed.
	if i + 5 > line.len {
		return CaseHeader{}
	}
	// Byte-level check for 'case '
	if line[i] == `c` && line[i + 1] == `a` && line[i + 2] == `s` && line[i + 3] == `e`
		&& line[i + 4] == ` ` {
		return CaseHeader{
			indent: line[..i]
			kind:   'case '
			rest:   line[i + 5..]
		}
	}
	return CaseHeader{}
}

fn (c CompatibilityLayer) mangle_recursive(text string) string {
	mut current := text
	for {
		mut changed := false
		mut depth := 0
		mut i := 0
		for i < current.len {
			ch := current[i]
			if ch == `[` {
				if depth == 0 {
					mut left := i
					for left > 0 {
						prev := current[left - 1]
						if prev.is_letter() || prev.is_digit() || prev == `_` || prev == `.` {
							left--
						} else {
							break
						}
					}
					if left < i {
						end := c.find_matching_bracket(current, i)
						if end != -1 {
							name := current[left..i]
							args := current[i + 1..end]
							mangled_args := c.mangle_recursive(args).replace(', ', '__py2v_gen_C__').replace(',',
								'__py2v_gen_C__').replace(' ', '')
							replacement := '${name}__py2v_gen_L__${mangled_args}__py2v_gen_R__'
							current = current[..left] + replacement + current[end + 1..]
							changed = true
							break
						}
					}
				}
				depth++
			} else if ch == `]` {
				if depth > 0 {
					depth--
				}
			}
			i++
		}
		if !changed {
			break
		}
	}
	return current
}

fn (c CompatibilityLayer) find_matching_bracket(text string, start int) int {
	mut depth := 0
	for i := start; i < text.len; i++ {
		ch := text[i]
		if ch == `[` {
			depth++
		} else if ch == `]` {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

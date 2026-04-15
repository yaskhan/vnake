module base

// NamingMixin - mixin for naming utilities and identifier sanitization

// to_snake_case converts CamelCase or UPPER_CASE to snake_case.
// This version is optimized for ASCII performance while maintaining UTF-8 correctness.
pub fn to_snake_case(name string) string {
	if name.len == 0 || name == '_' {
		return name
	}

	// Preserve internal markers
	if name.contains('__py2v_gen') {
		return name
	}

	// Handle TypeVars only if they are single letters (V generic parameters)
	if name.len == 1 && name.is_upper() {
		return name
	}

	// Fast path for ASCII strings
	if name.is_ascii() {
		mut already_snake := true
		for i := 0; i < name.len; i++ {
			ch := name[i]
			if ch.is_capital() {
				already_snake = false
				break
			}
			if ch == `_` && i > 0 && name[i - 1] == `_` {
				already_snake = false
				break
			}
		}
		if already_snake {
			return name
		}

		mut res := []u8{cap: name.len + 2}
		for i := 0; i < name.len; i++ {
			ch := name[i]
			if ch.is_capital() && i > 0 {
				prev := name[i - 1]
				if prev == `_` {
					// skip
				} else if is_lower_ascii(prev) {
					res << `_`
				} else if i + 1 < name.len && is_lower_ascii(name[i + 1]) {
					res << `_`
				}
			}
			if ch == `_` {
				if i > 0 && name[i-1] == `_` {
					continue
				}
			}
			if ch.is_capital() {
				res << ch + 32
			} else {
				res << ch
			}
		}
		return res.bytestr()
	}

	// Fallback for UTF-8 strings
	if name.contains('_') {
		mut parts := []string{}
		for p in name.split('_') {
			if p.len > 0 {
				parts << to_snake_case(p)
			}
		}
		if parts.len > 0 {
			return parts.join('_')
		}
		return '_'
	}

	mut res := []string{}
	for i, ch in name {
		if ch.is_capital() && i > 0 {
			if is_lower_ascii(name[i - 1]) {
				res << '_'
			} else if i + 1 < name.len && is_lower_ascii(name[i + 1]) {
				res << '_'
			}
		}
		res << ch.ascii_str().to_lower()
	}
	return res.join('')
}

// to_camel_case converts snake_case to camelCase (e.g., run_task -> runTask)
pub fn to_camel_case(name string) string {
	if name.len == 0 { return name }
	mut res := []u8{cap: name.len}
	mut next_upper := false
	for i := 0; i < name.len; i++ {
		ch := name[i]
		if ch == `_` {
			next_upper = true
		} else {
			if next_upper {
				if ch >= `a` && ch <= `z` {
					res << ch - 32
				} else {
					res << ch
				}
				next_upper = false
			} else {
				res << ch
			}
		}
	}
	return res.bytestr()
}

// get_factory_name returns snake_case factory name for the given struct name
pub fn get_factory_name(struct_name string, hierarchy map[string][]string) string {
	base_name := struct_name.split('[')[0]
	sanitized := to_snake_case(base_name)

	mut is_split_base := false
	for _, bases in hierarchy {
		if base_name in bases {
			is_split_base = true
			break
		}
	}

	if is_split_base {
		return 'new_${sanitized.to_lower()}_impl'
	}

	return 'new_${sanitized.to_lower()}'
}

// is_v_reserved_keyword checks if the name is a V reserved keyword.
// This is optimized to use a match Expression for faster lookup.
pub fn is_v_reserved_keyword(name string) bool {
	return match name {
		'fn', 'type', 'struct', 'mut', 'if', 'else', 'for', 'return', 'match', 'interface',
		'enum', 'pub', 'import', 'module', 'const', 'unsafe', 'defer', 'go', 'chan', 'shared',
		'spawn', 'assert', 'sizeof', 'typeof', '__global', 'as', 'in', 'is', 'none', 'map',
		'array', 'string', 'bool', 'Any', 'union', 'layout', 'stop', 'start' {
			true
		}
		else {
			false
		}
	}
}

// is_v_reserved_type checks if the name is a V reserved type.
// This is optimized to use a match Expression for faster lookup.
pub fn is_v_reserved_type(name string) bool {
	return match name {
		'int', 'string', 'bool', 'f64', 'f32', 'i64', 'byte', 'rune', 'void', 'Any', 'none',
		'i8', 'i16', 'i32', 'u16', 'u32', 'u64' {
			true
		}
		else {
			false
		}
	}
}

// sanitize_name sanitizes Python identifiers to comply with V
pub fn sanitize_name(name string, is_type bool, reserved_words map[string]bool, scc_prefix string, local_vars map[string]bool) string {
	if name.len == 0 {
		return name
	}

	// V reserved types are kept as is
	if is_v_reserved_type(name) {
		return name
	}

	// Internal markers are kept as is
	if name.contains('__py2v_gen') {
		return name
	}

	// V compliance: no leading underscores
	mut clean_name := name
	mut prefix_count := 0
	for clean_name.starts_with('_') && clean_name != '_' {
		prefix_count++
		clean_name = clean_name[1..]
	}

	if clean_name.len == 0 {
		return '_'.repeat(prefix_count)
	}

	if is_type {
		// PascalCase for types - Optimized single-pass implementation
		mut res_bytes := []u8{cap: clean_name.len}
		mut next_upper := true
		for i := 0; i < clean_name.len; i++ {
			ch := clean_name[i]
			if ch == `_` {
				next_upper = true
			} else {
				if next_upper {
					if ch >= `a` && ch <= `z` {
						res_bytes << ch - 32
					} else {
						res_bytes << ch
					}
					next_upper = false
				} else {
					res_bytes << ch
				}
			}
		}
		mut res := res_bytes.bytestr()
		res += '_'.repeat(prefix_count)

		if res in reserved_words || is_v_reserved_keyword(res) {
			return 'Py${res}'
		}
		return res
	}

	// Others: snake_case
	mut sanitized := to_snake_case(clean_name)
	sanitized += '_'.repeat(prefix_count)

	if sanitized in reserved_words || is_v_reserved_keyword(sanitized) {
		return 'py_${sanitized}'
	}

	// SCC collision
	if scc_prefix.len > 0 && !sanitized.starts_with('py_') && sanitized !in local_vars {
		if !sanitized.starts_with(scc_prefix + '__') {
			return '${scc_prefix}__${sanitized}'
		}
	}

	return sanitized
}
 
// is_simple_mut_target checks if the Expression is a simple identifier or attribute access that can be marked as mut in V.
pub fn is_simple_mut_target(expr string) bool {
	if expr.contains('(') || expr.contains(' ') || expr.contains('{') {
		return false
	}
	return true
}

// sanitize_name_helper - simple proxy for sanitize_name
pub fn sanitize_name_helper(name string, is_type bool) string {
	return sanitize_name(name, is_type, map[string]bool{}, '', map[string]bool{})
}

// mangle_name implements Python name mangling rules for private attributes
pub fn mangle_name(name string, class_name string) string {
	if class_name.len > 0 && name.starts_with('__') && !name.ends_with('__') {
		s_class := sanitize_name(class_name, true, map[string]bool{}, '', map[string]bool{}).trim_right('_')
		s_name := sanitize_name(name, false, map[string]bool{}, '', map[string]bool{})
		return '${s_class}_${s_name}'
	}
	return name
}

// local_vars_in_scope returns all local names from the current scope.
pub fn local_vars_in_scope(scope_stack []map[string]bool) map[string]bool {
	if scope_stack.len == 0 {
		return map[string]bool{}
	}
	return scope_stack[scope_stack.len - 1].clone()
}

// find_defining_class_for_static_method locates where a static/class method is defined.
pub fn find_defining_class_for_static_method(class_name string, method_name string, static_methods map[string][]string, class_methods map[string][]string, class_hierarchy map[string][]string) ?string {
	mut visited := map[string]bool{}
	mut stack := [class_name]
	for stack.len > 0 {
		curr := stack[stack.len - 1]
		stack = stack[..stack.len - 1].clone()
		if curr in visited {
			continue
		}
		visited[curr] = true

		if curr in static_methods && method_name in static_methods[curr] {
			return curr
		}
		if curr in class_methods && method_name in class_methods[curr] {
			return curr
		}

		if curr in class_hierarchy {
			for base in class_hierarchy[curr] {
				stack << base
			}
		}
	}
	return none
}

// get_full_self_type returns a type name for Self with active generics.
pub fn get_full_self_type(struct_name string, current_class string, current_class_generics []string) string {
	name := if struct_name.len > 0 {
		struct_name
	} else if current_class.len > 0 {
		current_class
	} else {
		'Self'
	}
	if current_class_generics.len == 0 {
		return name
	}
	return '${name}[${current_class_generics.join(', ')}]'
}

// find_defining_class_for_class_var locates a class where a class variable is declared.
pub fn find_defining_class_for_class_var(class_name string, var_name string, class_vars map[string][]map[string]string, class_hierarchy map[string][]string) ?string {
	mut visited := map[string]bool{}
	mut stack := [class_name]
	for stack.len > 0 {
		curr := stack.pop()
		if curr in visited {
			continue
		}
		visited[curr] = true

		if curr in class_vars {
			for var_info in class_vars[curr] {
				if var_info['name'] == var_name {
					return curr
				}
			}
		}

		if curr in class_hierarchy {
			for base in class_hierarchy[curr] {
				stack << base
			}
		}
	}
	return none
}

fn is_lower_ascii(ch u8) bool {
	return ch >= `a` && ch <= `z`
}

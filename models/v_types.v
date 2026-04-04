module models

// VType - V data types
pub enum VType {
	int
	float
	string
	bool
	void_
	list
	dict
	tuple
	none
	unknown
}

// get_tuple_struct_name generates struct name for Python Tuple
pub fn get_tuple_struct_name(types_str string) string {
	field_types := types_str.split(',').map(it.trim_space())
	mut name_parts := []string{}
	for t in field_types {
		mut clean_t := t.replace('builtins.', '').replace('typing.', '').replace('.', '').replace('[', '').replace(']', '').capitalize()
		if clean_t.len == 0 {
			clean_t = 'Any'
		}
		if clean_t == 'Str' { clean_t = 'String' }
		name_parts << clean_t
	}
	return 'TupleStruct_${name_parts.join('')}'
}

// map_python_type_to_v maps Python type to V type
pub fn map_python_type_to_v(py_type string, self_name string, allow_union bool, generic_map map[string]string, sum_type_registrar fn (string) string, literal_registrar fn ([]string) string, tuple_registrar fn (string) string) string {
	if py_type.len == 0 {
		return 'void'
	}
	if py_type.starts_with('[]') || py_type.starts_with('map[') || py_type.starts_with('datatypes.') {
		return py_type
	}

	// Handle leading * for TypeVarTuple
	mut clean_type := py_type
	if clean_type.starts_with('*') && !clean_type.starts_with('**') {
		clean_type = clean_type[1..]
	}

	// Strip surrounding quotes
	for clean_type.len > 0 && ((clean_type.starts_with("'") && clean_type.ends_with("'"))
		|| (clean_type.starts_with('"') && clean_type.ends_with('"'))) {
		clean_type = clean_type[1..clean_type.len - 1]
	}

	// Handle Mypy specific: tuple[int, int, fallback=Point]
	if clean_type.contains('fallback=') {
		mut fb_type := ''
		parts := clean_type.split('fallback=')
		if parts.len > 1 {
			fb_part := parts[1]
			comma_idx := fb_part.index(',') or { -1 }
			bracket_idx := fb_part.index(']') or { -1 }
			end_idx := if comma_idx >= 0 && (bracket_idx < 0 || comma_idx < bracket_idx) {
				comma_idx
			} else {
				bracket_idx
			}
			if end_idx >= 0 {
				fb_type = fb_part[..end_idx].trim_space()
			}
		}
		// If fallback is specific and not object, use it
		if fb_type.len > 0 && fb_type !in ['builtins.tuple', 'tuple', 'builtins.object', 'object'] {
			clean_fb := fb_type.replace(', fallback=', '').replace('fallback=', '')
			return map_python_type_to_v(clean_fb, self_name, allow_union, generic_map,
				sum_type_registrar, literal_registrar, tuple_registrar)
		}
		// Remove fallback= part from main type string
		if f_idx := clean_type.index(', fallback=') {
			clean_type = clean_type[..f_idx] + ']'
		}
	}

	if clean_type.ends_with('.args') { return '...Any' }
	if clean_type.ends_with('.kwargs') { return 'map[string]Any' }

	match clean_type {
		'int' { return 'int' }
		'float' { return 'f64' }
		'str' { return 'string' }
		'bool' { return 'bool' }
		'None' { return 'none' }
		'Any' { return 'Any' }
		'object' { return 'Any' }
		'builtins.int' { return 'int' }
		'builtins.float' { return 'f64' }
		'builtins.str' { return 'string' }
		'builtins.bool' { return 'bool' }
		'Callable', 'callable', 'typing.Callable', 'collections.abc.Callable' { return 'fn (...Any) Any' }
		else {}
	}
	
	// Handle Python 3.10+ union types: int | str
	if clean_type.contains('|') && !clean_type.contains('[') {
		parts := clean_type.split('|').map(it.trim_space())
		mut v_parts := []string{}
		for p in parts {
			v_parts << map_python_type_to_v(p, self_name, allow_union, generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
		}
		
		// Deduplicate
		mut unique_v_parts := []string{}
		for p in v_parts { if p !in unique_v_parts { unique_v_parts << p } }
		
		if 'Any' in unique_v_parts { return 'Any' }
		
		mut non_none := []string{}
		for t in unique_v_parts { if t != 'none' { non_none << t } }
		if non_none.len == 1 && unique_v_parts.len > 1 {
			return '?${non_none[0]}'
		}
		
		union_str := unique_v_parts.join(' | ')
		if !allow_union {
			reg_res := sum_type_registrar(union_str)
			if reg_res.len > 0 { return reg_res }
		}
		return union_str
	}

	if clean_type in generic_map {
		return generic_map[clean_type]
	}

	// Parse complex types
	if clean_type.contains('[') {
		return map_complex_type(clean_type, self_name, allow_union, generic_map, sum_type_registrar,
			literal_registrar, tuple_registrar)
	}

	// Sum type registration as fallback
	reg_res := sum_type_registrar(clean_type)
	if reg_res.len > 0 { return reg_res }

	// Basic type mapping fallback
	return map_basic_type(clean_type)
}

// map_complex_type handles complex types like List[int], Dict[str, Any]
fn map_complex_type(py_type string, self_name string, allow_union bool, generic_map map[string]string, sum_type_registrar fn (string) string, literal_registrar fn ([]string) string, tuple_registrar fn (string) string) string {
	 // eprintln('DEBUG MAP_COMPLEX: ${py_type}')
	bracket_idx := py_type.index('[') or { return map_basic_type(py_type) }
	base_type := py_type[..bracket_idx].trim_space()
	mut args_str := py_type[bracket_idx + 1..py_type.len - 1].trim_space()

	match base_type {
		'List', 'list', 'typing.List', 'typing.Sequence', 'typing.Iterable', 'Sequence', 'Iterable' {
			inner_type := if args_str.len > 0 {
				map_python_type_to_v(args_str, self_name, allow_union, generic_map, sum_type_registrar,
					literal_registrar, tuple_registrar)
			} else {
				'Any'
			}
			return '[]${inner_type}'
		}
		'Dict', 'dict', 'typing.Dict', 'typing.Mapping', 'Mapping' {
			mut key_type := 'string'
			mut val_type := 'Any'
			if args_str.len > 0 {
				parts := split_generic_args(args_str)
				if parts.len >= 2 {
					key_type = map_python_type_to_v(parts[0].trim_space(), self_name, allow_union,
						generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
					val_type = map_python_type_to_v(parts[1].trim_space(), self_name, allow_union,
						generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
				} else if parts.len == 1 {
					val_type = map_python_type_to_v(parts[0].trim_space(), self_name, allow_union,
						generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
				}
			}
			if key_type == 'Any' {
				key_type = 'string'
			}
			return 'map[${key_type}]${val_type}'
		}
		'Set', 'set', 'typing.Set' {
			inner_type := if args_str.len > 0 {
				map_python_type_to_v(args_str, self_name, allow_union, generic_map, sum_type_registrar,
					literal_registrar, tuple_registrar)
			} else {
				'Any'
			}
			return 'datatypes.Set[${inner_type}]'
		}
		'Tuple', 'tuple', 'typing.Tuple' {
			if args_str.len == 0 {
				return '[]Any'
			}
			parts := split_generic_args(args_str)
			if parts.len > 0 {
				mut v_parts := []string{}
				for p in parts {
					v_parts << map_python_type_to_v(p.trim_space(), self_name, allow_union,
						generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
				}
				tuple_res := tuple_registrar(v_parts.join(', '))
				if tuple_res.len > 0 {
					return tuple_res
				}
			}
			return '[]Any'
		}
		'Optional', 'typing.Optional' {
			inner_type := if args_str.len > 0 {
				map_python_type_to_v(args_str, self_name, allow_union, generic_map, sum_type_registrar,
					literal_registrar, tuple_registrar)
			} else {
				'Any'
			}
			if inner_type.starts_with('?') {
				return inner_type
			}
			return '?${inner_type}'
		}
		'Union', 'typing.Union' {
			if args_str.len == 0 {
				return 'Any'
			}
			parts := split_generic_args(args_str)
			mut v_parts := []string{}
			for p in parts {
				v_parts << map_python_type_to_v(p.trim_space(), self_name, allow_union,
					generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
			}

			mut unique := []string{}
			for p in v_parts {
				if p !in unique {
					unique << p
				}
			}

			if 'Any' in unique {
				return 'Any'
			}

			mut non_none := []string{}
			for t in unique {
				if t != 'none' {
					non_none << t
				}
			}
			if non_none.len == 1 && unique.len > 1 {
				return '?${non_none[0]}'
			}

			union_str := unique.join(' | ')
			if !allow_union {
				reg_res := sum_type_registrar(union_str)
				if reg_res.len > 0 {
					return reg_res
				}
			}
			return union_str
		}
		'Literal', 'typing.Literal' {
			parts := split_generic_args(args_str)
			res := literal_registrar(parts)
			if res.len > 0 {
				return res
			}
			return 'Any'
		}
		'Callable', 'typing.Callable', 'collections.abc.Callable' {
			if args_str.len > 0 {
				parts := split_generic_args(args_str)
				if parts.len >= 2 {
					mut arg_types := []string{}
					args_part := parts[0].trim_space()
					if args_part.starts_with('[') && args_part.ends_with(']') {
						inner_args := args_part[1..args_part.len - 1].trim_space()
						if inner_args.len > 0 {
							arg_parts := split_generic_args(inner_args)
							for p in arg_parts {
								arg_types << map_python_type_to_v(p.trim_space(), self_name, allow_union, generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
							}
						}
					} else if args_part == '...' {
						arg_types << '...Any'
					} else {
						arg_types << map_python_type_to_v(args_part, self_name, allow_union, generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
					}
					
					ret_type := map_python_type_to_v(parts[1].trim_space(), self_name, allow_union, generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
					if ret_type == 'none' || ret_type == 'void' {
						return 'fn (${arg_types.join(", ")})'
					}
					return 'fn (${arg_types.join(", ")}) ${ret_type}'
				}
			}
			return 'fn (...Any) Any'
		}
		'TypeGuard', 'TypeIs', 'typing.TypeGuard', 'typing.TypeIs' {
			return 'bool'
		}
		'TypeForm', 'typing.TypeForm', 'typing_extensions.TypeForm' {
			return 'string'
		}
		'Final', 'ClassVar', 'Annotated', 'Required', 'NotRequired', 'ReadOnly',
		'typing.Final', 'typing.ClassVar', 'typing.Annotated', 'typing.Required', 'typing.NotRequired',
		'typing.ReadOnly' {
			if args_str.len > 0 {
				parts := split_generic_args(args_str)
				inner := map_python_type_to_v(parts[0].trim_space(), self_name, allow_union,
					generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
				if base_type in ['NotRequired', 'typing.NotRequired'] && !inner.starts_with('?') {
					return '?${inner}'
				}
				return inner
			}
			return 'Any'
		}
		else {}
	}

	res := map_basic_type(base_type)
	if args_str.len > 0 {
		mut v_args := []string{}
		parts := split_generic_args(args_str)
		for p in parts {
			v_args << map_python_type_to_v(p.trim_space(), self_name, allow_union, generic_map, sum_type_registrar, literal_registrar, tuple_registrar)
		}
		return '${res}[${v_args.join(", ")}]'
	}
	return res
}

// split_generic_args separates top-level generic arguments while respecting nested brackets.
// Optimization: Uses a start index and string slicing to avoid repeated O(N) string concatenations.
fn split_generic_args(s string) []string {
	mut result := []string{}
	mut depth := 0
	mut start := 0
	for i := 0; i < s.len; i++ {
		ch := s[i]
		match ch {
			`[` {
				depth++
			}
			`]` {
				depth--
			}
			`,` {
				if depth == 0 {
					result << s[start..i].trim_space()
					start = i + 1
				}
			}
			else {}
		}
	}
	if start < s.len {
		tail := s[start..].trim_space()
		if tail.len > 0 {
			result << tail
		}
	}
	return result
}

// map_basic_type maps common Python type names to V equivalents.
// Optimization: Uses a match expression instead of a map literal to avoid re-allocation
// on every call. Redundant prefixed entries (e.g. typing.Any) are removed as they are
// already handled by prefix-stripping logic.
fn map_basic_type(name string) string {
	mut clean_name := name
	if clean_name.starts_with('typing.') {
		clean_name = clean_name[7..]
	} else if clean_name.starts_with('typing_extensions.') {
		clean_name = clean_name[18..]
	} else if clean_name.starts_with('builtins.') {
		clean_name = clean_name[9..]
	}
	clean_name = clean_name.trim_space()

	return match clean_name {
		'int' { 'int' }
		'float' { 'f64' }
		'str' { 'string' }
		'bytes' { '[]u8' }
		'bool' { 'bool' }
		'None' { 'none' }
		'Any', 'object' { 'Any' }
		'list', 'List', 'Sequence', 'Iterable' { '[]Any' }
		'dict', 'Dict', 'Mapping' { 'map[string]Any' }
		'tuple', 'Tuple' { '[]Any' }
		'set', 'Set' { 'datatypes.Set[Any]' }
		'memoryview', 'bytearray' { '[]u8' }
		'IO', 'TextIO', 'BinaryIO' { 'os.File' }
		'StringIO', 'io.StringIO' { 'strings.Builder' }
		'NoReturn' { 'noreturn' }
		'Optional' { '?Any' }
		'Union' { 'Any' }
		'Callable', 'callable', 'collections.abc.Callable' { 'fn (...Any) Any' }
		'LiteralString' { 'string' }
		'TypeForm', 'type', 'Final', 'ClassVar', 'ForwardRef', 'Annotated', 'Required', 'NotRequired', 'ReadOnly', 'annotationlib.ForwardRef' { 'Any' }
		else { clean_name }
	}
}

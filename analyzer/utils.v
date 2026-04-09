module analyzer

import ast

pub fn expr_name(node ast.Expression) string {
	return match node {
		ast.Name { node.id }
		ast.Attribute {
			base := expr_name(node.value)
			if base.len > 0 {
				'${base}.${node.attr}'
			} else {
				node.attr
			}
		}
		ast.Subscript {
			expr_name(node.value)
		}
		else {
			''
		}
	}
}

pub struct TypeInferenceUtilsMixin {
	TypeInferenceBase
}

pub fn new_type_inference_utils_mixin() TypeInferenceUtilsMixin {
	return TypeInferenceUtilsMixin{
		TypeInferenceBase: new_type_inference_base()
	}
}

pub fn (t &TypeInferenceUtilsMixin) get_ancestors(typ string) []string {
	mut ancestors := [typ]
	if typ in t.class_hierarchy {
		for base in t.class_hierarchy[typ] {
			ancestors << t.get_ancestors(base)
		}
	}
	return ancestors
}

pub fn (t &TypeInferenceUtilsMixin) get_depth(typ string, current_depth int) int {
	if typ !in t.class_hierarchy || t.class_hierarchy[typ].len == 0 {
		return current_depth
	}
	mut max_d := current_depth
	for base in t.class_hierarchy[typ] {
		d := t.get_depth(base, current_depth + 1)
		if d > max_d {
			max_d = d
		}
	}
	return max_d
}

pub fn (mut t TypeInferenceUtilsMixin) find_lcs(types []string) string {
	if types.len == 0 {
		return 'Any'
	}
	mut unique_types := []string{}
	for typ in types {
		if typ !in unique_types {
			unique_types << typ
		}
	}
	if unique_types.len == 1 {
		return unique_types[0]
	}

	mut ancestor_lists := [][]string{}
	for typ in unique_types {
		ancestor_lists << t.get_ancestors(typ)
	}

	mut common := map[string]bool{}
	for anc in ancestor_lists[0] {
		common[anc] = true
	}

	for i := 1; i < ancestor_lists.len; i++ {
		mut current_anc := map[string]bool{}
		for anc in ancestor_lists[i] {
			current_anc[anc] = true
		}
		for k, _ in common {
			if k !in current_anc {
				common.delete(k)
			}
		}
	}

	if common.len == 0 {
		return 'Any'
	}

	mut lcs := 'Any'
	mut max_depth := -1
	for candidate, _ in common {
		d := t.get_depth(candidate, 0)
		if d > max_depth {
			max_depth = d
			lcs = candidate
		}
	}

	return lcs
}

pub fn (mut t TypeInferenceUtilsMixin) mark_mutated(name string) {
	mut info := t.get_mutability(name)
	info.is_mutated = true
	t.set_mutability(name, info)
}

pub fn (mut t TypeInferenceUtilsMixin) mark_reassigned(name string) {
	mut info := t.get_mutability(name)
	info.is_reassigned = true
	t.set_mutability(name, info)
}

pub fn (mut t TypeInferenceUtilsMixin) guess_node_type(node_type string) string {
	match node_type {
		'bool' {
			return 'bool'
		}
		'int' {
			return 'int'
		}
		'float', 'float64' {
			return 'f64'
		}
		'str', 'string' {
			return 'string'
		}
		'bytes', 'bytearray', 'memoryview' {
			return '[]u8'
		}
		else {
			if t.has_type(node_type) {
				return t.get_type(node_type)
			}
			if node_type.len > 0 && node_type[0].is_capital() {
				return node_type
			}
			return 'Any'
		}
	}
}

pub fn map_python_type_to_v(py_type string) string {
	mut clean_type := py_type.trim_space().trim('\'"')
	if clean_type.starts_with('typing_extensions.') {
		clean_type = clean_type[18..]
	}
	if clean_type.starts_with('typing.') {
		clean_type = clean_type[7..]
	}
	if clean_type.starts_with('builtins.') {
		clean_type = clean_type[9..]
	}
	if clean_type in ['LiteralString', 'typing.LiteralString', 'typing_extensions.LiteralString'] {
		return 'string'
	}
	match clean_type {
		'int' {
			return 'int'
		}
		'i64', 'mypy_extensions.i64' {
			return 'i64'
		}
		'float' {
			return 'f64'
		}
		'str', 'string' {
			return 'string'
		}
		'bool' {
			return 'bool'
		}
		'bytes' {
			return '[]u8'
		}
		'bytearray' {
			return '[]u8'
		}
		'None' {
			return 'none'
		}
		'Any' {
			return 'Any'
		}
		'object' {
			return 'Any'
		}
		'dict' {
			return 'map[string]Any'
		}
		'list' {
			return '[]Any'
		}
		'tuple' {
			return '[]Any'
		}
		'set' {
			return 'datatypes.Set[Any]'
		}
		else {
			if clean_type.starts_with('List[') || clean_type.starts_with('list[') {
				inner := clean_type[5..clean_type.len - 1]
				return '[]' + map_python_type_to_v(inner)
			}
			if clean_type.starts_with('Dict[') || clean_type.starts_with('dict[') {
				mut inner := clean_type[5..clean_type.len - 1]
				if inner.len > 0 {
					parts := inner.split(',')
					if parts.len >= 2 {
						key_type := map_python_type_to_v(parts[0].trim_space())
						val_type := map_python_type_to_v(parts[1].trim_space())
						return 'map[${key_type}]${val_type}'
					}
				}
				return 'map[string]Any'
			}
			if clean_type.starts_with('Set[') || clean_type.starts_with('set[') {
				inner := clean_type[4..clean_type.len - 1]
				return 'datatypes.Set[' + map_python_type_to_v(inner) + ']'
			}
			if clean_type.starts_with('Optional[') {
				inner := clean_type[9..clean_type.len - 1]
				return '?' + map_python_type_to_v(inner)
			}
			if clean_type.starts_with('Union[') {
				inner := clean_type[6..clean_type.len - 1]
				parts := inner.split(',').map(it.trim_space())
				mut non_none := []string{}
				for part in parts {
					if part != 'None' {
						non_none << map_python_type_to_v(part)
					}
				}
				if non_none.len == 1 && parts.len > 1 {
					return '?' + non_none[0]
				}
				return if non_none.len > 0 { non_none.join(' | ') } else { 'Any' }
			}
			if clean_type.contains('|') {
				parts := clean_type.split('|').map(it.trim_space())
				mut mapped := []string{}
				for p in parts {
					mapped << map_python_type_to_v(p)
				}
				
				// Optional check
				mut has_none := false
				mut others := []string{}
				for m in mapped {
					if m == 'none' { has_none = true }
					else { others << m }
				}
				if has_none && others.len == 1 {
					return '?' + others[0]
				}
				
				return mapped.join(' | ')
			}
			return clean_type
		}
	}
}

module base

import ast
import models

pub const op_methods_to_symbols = {
	'__add__':      '+'
	'__sub__':      '-'
	'__mul__':      '*'
	'__truediv__':  '/'
	'__mod__':      '%'
	'__pow__':      '**'
	'__matmul__':   '@'
	'__and__':      '&'
	'__or__':       '|'
	'__xor__':      '^'
	'__lshift__':   '<<'
	'__rshift__':   '>>'
	'__eq__':       '=='
	'__ne__':       '!='
	'__lt__':       '<'
	'__ge__':       '>='
	'__gt__':       '>'
	'__le__':       '<='
	'__contains__': 'in'
}

pub struct TypeUtilsContext {
pub mut:
	imported_symbols    map[string]string
	defined_classes     map[string]map[string]bool
	scc_files           []string
	used_builtins    map[string]bool
	warnings         []string
	include_all_symbols bool
	strict_exports      bool
}

pub struct TypeMapOptions {
pub:
	struct_name        string
	allow_union        bool = true
	register_sum_types bool = true
	is_return          bool
	self_type          string = 'Self'
	generic_map        map[string]string
}

pub fn is_collection_type(v_type string) bool {
	return v_type.starts_with('[]') || v_type.starts_with('map[')
		|| v_type.starts_with('datatypes.Set[') || v_type == 'string' || v_type == 'LiteralString'
}

pub fn is_clonable_collection(v_type string) bool {
	return v_type.starts_with('[]') || v_type.starts_with('map[')
}

pub fn is_tuple_struct(v_type string) bool {
	return v_type.starts_with('TupleStruct_')
}

pub fn is_string_type(v_type string) bool {
	return v_type == 'string' || v_type == 'LiteralString'
}

pub fn is_numeric_type(v_type string) bool {
	return v_type in ['int', 'f64', 'i64', 'u32', 'u64', 'i8', 'i16', 'u8', 'u16']
}

// wrap_bool lowers Python truthiness into explicit V boolean checks.
pub fn wrap_bool(node ast.Expression, expr string, v_type string, invert bool) string {
	if node is ast.BoolOp || node is ast.Compare || node is ast.UnaryOp {
		if node is ast.UnaryOp && node.op.value != 'not' {
			// pass
		} else {
			return if invert { '!(${expr})' } else { expr }
		}
	}

	if v_type.starts_with('?') {
		inner := v_type[1..]
		inner_cond := bool_condition(expr, inner, invert)
		if invert {
			if inner_cond.len > 0 {
				return '(${expr} == none || ${inner_cond})'
			}
			return '${expr} == none'
		}
		if inner_cond.len > 0 {
			return '(${expr} != none && ${inner_cond})'
		}
		return '${expr} != none'
	}

	if v_type == 'none' {
		return if invert { 'true' } else { 'false' }
	}
	if v_type == 'bool' {
		return if invert { '!${expr}' } else { expr }
	}
	if v_type == 'Any' {
		eprintln('DEBUG: base.wrap_bool Any type found for expr=${expr} invert=${invert}')
		return if invert { '!py_bool(${expr})' } else { 'py_bool(${expr})' }
	}
	return bool_condition(expr, v_type, invert)
}

fn bool_condition(expr string, v_type string, invert bool) string {
	if is_collection_type(v_type) {
		op := if invert { '==' } else { '>' }
		return '${expr}.len ${op} 0'
	}
	if is_numeric_type(v_type) {
		op := if invert { '==' } else { '!=' }
		return '${expr} ${op} 0'
	}
	if v_type == 'bool' {
		return if invert { '!${expr}' } else { expr }
	}
	if v_type == 'Any' {
		return if invert { '!py_bool(${expr})' } else { 'py_bool(${expr})' }
	}
	return if invert { '!${expr}' } else { expr }
}

// build_truthiness_check builds a V condition that checks Python truthiness for a value.
// For optional types, it checks both != none AND the inner type's truthiness.
// For Any types, it uses py_bool and checks for none.
// This is used for `or`/`and` Expressions to correctly handle None values.
pub fn build_truthiness_check(expr string, v_type string) string {
	// Optional types: must check != none first, then check inner value
	if v_type.starts_with('?') {
		inner := v_type[1..]
		inner_check := truthiness_condition(expr, inner)
		if inner_check.len > 0 {
			return '(${expr} != none && ${inner_check})'
		}
		return '${expr} != none'
	}
	
	// Any type needs py_bool check with none handling
	if v_type == 'Any' {
		return '(${expr} != none && py_bool(${expr}))'
	}
	
	return truthiness_condition(expr, v_type)
}

// truthiness_condition returns the condition that checks if a value is truthy for non-optional types.
fn truthiness_condition(expr string, v_type string) string {
	if is_collection_type(v_type) {
		return '${expr}.len > 0'
	}
	if is_numeric_type(v_type) {
		return '${expr} != 0'
	}
	if v_type == 'bool' {
		return expr
	}
	if v_type == 'Any' {
		return 'py_bool(${expr})'
	}
	return expr
}

// map_type is a centralized Python-to-V type mapper with post-processing.
pub fn map_type(type_str string, opts TypeMapOptions, mut ctx TypeUtilsContext, sum_type_registrar fn (string) string, literal_registrar fn ([]string) string, tuple_registrar fn (string) string) string {
	if type_str.contains('TypeForm') {
		ctx.warnings << "Experimental feature 'TypeForm' is used."
	}

	registrar := if opts.register_sum_types {
		sum_type_registrar
	} else {
		fn (_ string) string {
			return ''
		}
	}
	tup_registrar := if opts.register_sum_types {
		tuple_registrar
	} else {
		fn (_ string) string {
			return ''
		}
	}

	mut v_type := models.map_python_type_to_v(type_str, opts.self_type, opts.allow_union,
		opts.generic_map, registrar, literal_registrar, tup_registrar)
	if v_type.contains('map[Any]') {
		v_type = v_type.replace('map[Any]', 'map[string]')
	}
	if opts.is_return && v_type == 'none' {
		return 'void'
	}
	if v_type == 'LiteralString' {
		v_type = 'string'
	}

	basic_v_types := ['Any', 'int', 'string', 'bool', 'void', 'none', 'f64', 'i64', 'u32', 'u64',
		'i8', 'i16', 'u8', 'u16', 'Final', 'ClassVar', 'LiteralString', 'noreturn']
	if v_type in basic_v_types {
		return v_type
	}

	if v_type in ctx.imported_symbols {
		return ctx.imported_symbols[v_type]
	}

	if v_type.contains('.') {
		parts := v_type.split('.')
		if parts.len > 1 {
			module_prefix := parts[..parts.len - 1].join('.')
			typename := parts[parts.len - 1]
			
			// Handle Nested Classes: Outer.Inner -> Outer_Inner
			nested_name := v_type.replace('.', '_')
			if nested_name in ctx.defined_classes {
				return nested_name
			}

			for f in ctx.scc_files {
				norm := f.replace('.py', '').replace('/', '.').replace('\\', '.')
				if module_prefix.ends_with(norm) {
					prefix := get_scc_prefix(f)
					return '${prefix}__${typename}'
				}
			}
		}
	}

	if !opts.allow_union && v_type.contains(' | ') {
		// Convert "A | B" to "SumType_AB", with sorted parts for determinism
		mut parts := v_type.split(' | ')
		parts.sort()
		mut name_parts := []string{}
		for p in parts {
			mut part_name := p.capitalize()
			if part_name == 'Str' {
				part_name = 'String'
			}
			name_parts << part_name
		}
		st_name := 'SumType_${name_parts.join('')}'
		registrar(st_name)
		return st_name
	}

	return v_type
}

pub fn get_v_default_value(v_type string, active_v_generics []string) string {
	if v_type.starts_with('?') {
		return 'none'
	}
	if v_type in ['int', 'i64', 'u32', 'u64', 'i8', 'i16', 'u8', 'u16'] {
		return '0'
	}
	if v_type in ['f64', 'f32'] {
		return '0.0'
	}
	if v_type == 'bool' {
		return 'false'
	}
	if v_type == 'string' {
		return "'0'"
	}
	if v_type.starts_with('[]') || v_type.starts_with('map[') {
		return '${v_type}{}'
	}
	if v_type == 'Any' {
		return 'Any(NoneExpr{})'
	}
	if v_type.len > 0 && v_type[0].is_capital() && !v_type.contains('|') {
		if v_type in active_v_generics {
			return 'py_zero[${v_type}]()'
		}
		return '${v_type}{}'
	}
	return 'none'
}

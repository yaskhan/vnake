module translator

import base

fn to_snake_case(name string) string {
	return base.to_snake_case(name)
}

@[heap]
pub struct VCodeEmitter {
pub mut:
	module_name      string
	imports          []string
	structs          []string
	functions        []string
	main_body        []string
	init_body        []string
	globals          []string
	constants        []string
	helper_imports   []string
	helper_structs   []string
	helper_functions []string
	used_builtins    map[string]bool
	defined_classes  map[string]bool
	omit_builtins    bool
}

pub fn new_vcode_emitter(module_name string) VCodeEmitter {
	return VCodeEmitter{
		module_name:      module_name
		imports:          []string{}
		structs:          []string{}
		functions:        []string{}
		main_body:        []string{}
		init_body:        []string{}
		globals:          []string{}
		constants:        []string{}
		helper_imports:   []string{}
		helper_structs:   []string{}
		helper_functions: []string{}
		used_builtins:    map[string]bool{}
		defined_classes:  map[string]bool{}
		omit_builtins:    false
	}
}

pub fn (mut e VCodeEmitter) add_import(module_name string) {
	if module_name !in e.imports {
		e.imports << module_name
	}
}

pub fn (mut e VCodeEmitter) add_helper_import(module_name string) {
	if module_name !in e.helper_imports {
		e.helper_imports << module_name
	}
}

pub fn (mut e VCodeEmitter) add_global(global_def string) {
	mut name := global_def.trim_space()
	if name.starts_with('__global ') {
		name = name['__global '.len..].trim_space()
	}
	if name.contains(' ') {
		name = name.all_before(' ')
	}

	for existing in e.globals {
		mut ex_name := existing.trim_space()
		if ex_name.starts_with('__global ') {
			ex_name = ex_name['__global '.len..].trim_space()
		}
		if ex_name.contains(' ') {
			ex_name = ex_name.all_before(' ')
		}
		if name == ex_name {
			return
		}
	}
	e.globals << global_def
}

pub fn (mut e VCodeEmitter) add_constant(const_def string) {
	mut updated := const_def
	if const_def.starts_with('pub const ') {
		name_part := const_def[10..]
		if idx := name_part.index('=') {
			name := name_part[..idx].trim_space()
			rest := name_part[idx..]
			updated = 'pub const ${to_snake_case(name)} ${rest.trim_space()}'
		}
	} else if const_def.starts_with('const ') {
		name_part := const_def[6..]
		if idx := name_part.index('=') {
			name := name_part[..idx].trim_space()
			rest := name_part[idx..]
			updated = 'const ${to_snake_case(name)} ${rest.trim_space()}'
		}
	}
	e.constants << updated
}

pub fn (mut e VCodeEmitter) add_struct(struct_def string) {
	e.structs << struct_def
}

pub fn (mut e VCodeEmitter) add_helper_struct(struct_def string) {
	e.helper_structs << struct_def
}

pub fn (mut e VCodeEmitter) add_function(func_def string) {
	e.functions << func_def
}

pub fn (mut e VCodeEmitter) add_helper_function(func_def string) {
	e.helper_functions << func_def
}

pub fn (mut e VCodeEmitter) add_init_statement(stmt string) {
	e.init_body << stmt
}

pub fn (mut e VCodeEmitter) add_main_statement(stmt string) {
	e.main_body << stmt
}

pub fn (e &VCodeEmitter) emit() string {
	mut lines := []string{}
	lines << 'module ${e.module_name}'
	lines << ''

	if e.imports.len > 0 || e.helper_imports.len > 0 {
		mut all_imports := e.imports.clone()
		for imp in e.helper_imports {
			if imp !in all_imports {
				all_imports << imp
			}
		}
		all_imports.sort()
		for imp in all_imports {
			lines << 'import ${imp}'
		}
		lines << ''
	}

	if e.structs.len > 0 {
		lines << e.structs.join('\n\n')
		lines << ''
	}

	// Generate Any sum-type if not already present
	mut has_any := false
	for s in e.structs {
		if s.contains('type Any =') {
			has_any = true
			break
		}
	}
	for s in e.helper_structs {
		if s.contains('type Any =') {
			has_any = true
			break
		}
	}

	if !has_any && (e.used_builtins.len > 0 || e.defined_classes.len > 0) {
		mut variants := ['bool', 'f64', 'i64', 'int', 'string', 'voidptr', 'NoneType', '[]Any',
			'map[string]Any', 'map[i64]Any']
		variants << ['[]i64', '[]f64', '[]int']
		// ⚡ Bolt: Using a map for O(1) variant deduplication reduces complexity from O(C * V) to O(C).
		mut variants_seen := map[string]bool{}
		for v in variants {
			variants_seen[v] = true
		}
		for cls, _ in e.defined_classes {
			v_cls := cls.trim_left('&')
			if v_cls.len > 0 && v_cls[0].is_capital()
				&& v_cls !in ['NoneType', 'Any', 'LiteralString', 'Self', 'TaskState'] {
				target := '&' + v_cls
				if target !in variants_seen {
					variants_seen[target] = true
					variants << target
				}
			} else if v_cls !in variants_seen {
				variants_seen[v_cls] = true
				variants << v_cls
			}
		}
		lines << 'pub type Any = ${variants.join(' | ')}'
		lines << ''
		lines << 'pub struct NoneType {}'
		lines << 'pub fn (n NoneType) str() string { return "None" }'
		lines << ''
	}

	if e.helper_structs.len > 0 {
		lines << e.helper_structs.join('\n\n')
		lines << ''
	}

	if e.globals.len > 0 {
		lines << '// To compile with globals, use: v -enable-globals .'
		for g in e.globals {
			mut sanitized := g
			if sanitized.starts_with('pub ') {
				sanitized = sanitized[4..]
			}
			if sanitized.starts_with('__global ') {
				lines << sanitized
			} else {
				lines << '__global ${sanitized}'
			}
		}
		lines << ''
	}

	if e.constants.len > 0 {
		for c in e.constants {
			if c.starts_with('pub ') {
				lines << c
			} else {
				lines << c
			}
		}
		lines << ''
	}

	if e.functions.len > 0 {
		lines << e.functions.join('\n\n')
		lines << ''
	}

	if e.helper_functions.len > 0 {
		lines << e.helper_functions.join('\n\n')
		lines << ''
	}

	if e.init_body.len > 0 {
		lines << 'fn init() {'
		for stmt in e.init_body {
			lines << '    ${stmt}'
		}
		lines << '}'
		lines << ''
	}

	if e.main_body.len > 0 {
		lines << 'fn main() {'
		for stmt in e.main_body {
			lines << '    ${stmt}'
		}
		lines << '}'
	}

	return lines.join('\n')
}

pub fn (e &VCodeEmitter) raw_emit() string {
	mut lines := []string{}
	if e.imports.len > 0 {
		mut imps := e.imports.clone()
		imps.sort()
		for i in imps {
			lines << 'import ${i}'
		}
		lines << ''
	}
	if e.structs.len > 0 {
		lines << e.structs.join('\n\n')
		lines << ''
	}
	if e.helper_structs.len > 0 {
		lines << e.helper_structs.join('\n\n')
		lines << ''
	}
	if e.globals.len > 0 {
		for g in e.globals {
			mut sanitized := g.replace('pub ', '')
			if sanitized.starts_with('__global ') {
				lines << sanitized
			} else {
				lines << '__global ${sanitized}'
			}
		}
		lines << ''
	}
	if e.constants.len > 0 {
		for c in e.constants {
			lines << c
		}
		lines << ''
	}
	if e.functions.len > 0 {
		lines << e.functions.join('\n\n')
		lines << ''
	}
	if e.helper_functions.len > 0 {
		lines << e.helper_functions.join('\n\n')
		lines << ''
	}
	if e.main_body.len > 0 {
		for m in e.main_body {
			lines << m
		}
	}
	res := lines.join('\n').trim_space()
	if res.len == 0 && (e.structs.len > 0 || e.functions.len > 0 || e.constants.len > 0) {
		eprintln('BUG: raw_emit returning empty while collections populated! structs=${e.structs.len} funcs=${e.functions.len} consts=${e.constants.len}')
	}
	return res
}

pub fn (e &VCodeEmitter) emit_helpers() string {
	return VCodeEmitter.emit_global_helpers(e.helper_imports, e.helper_structs, e.helper_functions,
		'main', [], e.used_builtins)
}

pub fn VCodeEmitter.emit_global_helpers(imports []string, structs []string, functions []string, module_name string, classes []string, used_builtins map[string]bool) string {
	mut lines := []string{}
	lines << 'module ${module_name}'
	lines << ''

	mut seen_imports := map[string]bool{}
	mut unique_imports := []string{}
	for imp in imports {
		if imp !in seen_imports {
			seen_imports[imp] = true
			unique_imports << imp
		}
	}
	unique_imports.sort()
	for imp in unique_imports {
		lines << 'import ${imp}'
	}
	if unique_imports.len > 0 {
		lines << ''
	}

	mut variants := ['bool', 'f64', 'i64', 'int', 'string', 'voidptr', 'NoneType', '[]Any',
		'map[string]Any', 'map[i64]Any']
	variants << ['[]i64', '[]f64', '[]int', '[]Packet', '[]Task', '[]TaskRec']
	// ⚡ Bolt: Using a map for O(1) variant deduplication reduces complexity from O(C * V) to O(C).
	mut variants_seen := map[string]bool{}
	for v in variants {
		variants_seen[v] = true
	}
	if used_builtins['Template'] {
		if 'Interpolation' !in variants_seen {
			variants_seen['Interpolation'] = true
			variants << 'Interpolation'
		}
		if 'Template' !in variants_seen {
			variants_seen['Template'] = true
			variants << 'Template'
		}
	}
	for cls in classes {
		v_cls := cls.trim_left('&')
		// Ensure classes in Any are always references to match V 0.5 heap-allocated memory model for Python objects
		if v_cls.len > 0 && v_cls[0].is_capital()
			&& v_cls !in ['NoneType', 'Any', 'LiteralString', 'Self', 'TaskState'] {
			target := '&' + v_cls
			if target !in variants_seen {
				variants_seen[target] = true
				variants << target
			}
		} else if v_cls !in variants_seen {
			variants_seen[v_cls] = true
			variants << v_cls
		}
	}
	lines << 'pub type Any = ${variants.join(' | ')}'
	lines << ''

	lines << 'pub struct NoneType {}'
	lines << 'pub fn (n NoneType) str() string {'
	lines << "    return 'None'"
	lines << '}'
	lines << ''

	lines << 'pub fn py_bool(val Any) bool {
    if val is bool { return val }
    if val is int { return val != 0 }
    if val is i64 { return val != 0 }
    if val is f64 { return val != 0.0 }
    if val is string { return val.len > 0 }
    if val is []Any { return val.len > 0 }
    if val is map[string]Any { return val.len > 0 }
    if val is NoneType { return false }
    return true
}'
	lines << ''

	if used_builtins['Template'] {
		lines << 'pub struct Interpolation {'
		lines << 'pub:'
		lines << '    value       Any'
		lines << '    expression  string'
		lines << '    conversion  string'
		lines << '    format_spec string'
		lines << '}'
		lines << ''

		lines << 'pub struct Template {'
		lines << 'pub:'
		lines << '    strings        []string'
		lines << '    interpolations []Interpolation'
		lines << '}'
		lines << ''

		lines << 'pub fn (t Template) values() []Any {'
		lines << '    mut res := []Any{cap: t.interpolations.len}'
		lines << '    for i in t.interpolations {'
		lines << '        res << i.value'
		lines << '    }'
		lines << '    return res'
		lines << '}'
		lines << ''

		lines << 'pub fn (t1 Template) + (t2 Template) Template {'
		lines << '    if t1.strings.len == 0 { return t2 }'
		lines << '    if t2.strings.len == 0 { return t1 }'
		lines << '    mut new_strings := t1.strings[..t1.strings.len - 1].clone()'
		lines << '    new_strings << t1.strings.last() + t2.strings[0]'
		lines << '    if t2.strings.len > 1 {'
		lines << '        new_strings << t2.strings[1..]'
		lines << '    }'
		lines << '    mut new_interpolations := t1.interpolations.clone()'
		lines << '    new_interpolations << t2.interpolations'
		lines << '    return Template{'
		lines << '        strings: new_strings'
		lines << '        interpolations: new_interpolations'
		lines << '    }'
		lines << '}'
		lines << ''
	}

	if used_builtins['py_subscript'] {
		lines << 'pub fn py_subscript(val Any, idx Any) Any {'
		lines << '    if val is []Any {'
		lines << '        if idx is int { return val[idx] }'
		lines << '        if idx is i64 { return val[int(idx)] }'
		lines << '    }'
		lines << '    if val is map[string]Any {'
		lines << '        if idx is string { return val[idx] }'
		lines << '    }'
		lines << '    return NoneType{}'
		lines << '}'
		lines << ''
	}

	lines << 'pub enum PyAnnotationFormat { value forwardref string }'
	lines << ''

	lines << 'pub fn py_get_type_hints[T]() map[string]string {'
	lines << '    mut hints := map[string]string{}'
	lines << '    ' + '$' + 'for field in T.fields {'
	lines << '        hints[field.name] = field.typ'
	lines << '    }'
	lines << '    return hints'
	lines << '}'
	lines << ''

	lines << 'pub fn py_get_type_hints_generic(obj Any) map[string]string {'
	lines << '    return map[string]string{}'
	lines << '}'
	lines << ''

	mut seen_structs := map[string]bool{}
	for s in structs {
		if s !in seen_structs {
			seen_structs[s] = true
			lines << s
		}
	}
	if structs.len > 0 {
		lines << ''
	}

	mut seen_funcs := map[string]bool{}
	for f in functions {
		if f !in seen_funcs {
			seen_funcs[f] = true
			lines << f
		}
	}
	if functions.len > 0 {
		lines << ''
	}

	return lines.join('\n')
}

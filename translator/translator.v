module translator

import analyzer
import ast
import base
import expressions
import models
import classes
import functions

pub struct Translator {
pub mut:
	state    &base.TranslatorState
	analyzer &analyzer.Analyzer
	model    models.VType
	mutable_locals map[string]bool
	current_function_name string
	classes_module   classes.ClassesModule
	functions_module functions.FunctionsModule
}

pub fn new_translator(state &base.TranslatorState, type_analyzer &analyzer.Analyzer) &Translator {
	mut t := &Translator{
		state:    state
		analyzer: type_analyzer
		model:    models.VType{}
		mutable_locals: map[string]bool{}
		classes_module: classes.new_classes_module()
		functions_module: functions.new_functions_module()
	}
	return t
}

fn (mut t Translator) indent() string {
	return '\t'.repeat(t.state.indent_level)
}

fn (mut t Translator) emit(line string) {
	t.state.output << line
}

fn (mut t Translator) emit_indented(line string) {
	t.state.output << t.indent() + line
}


fn (mut t Translator) push_scope() {
	t.state.scope_stack << map[string]bool{}
}

fn (mut t Translator) pop_scope() {
	if t.state.scope_stack.len > 0 {
		t.state.scope_stack.delete_last()
	}
}

fn (mut t Translator) declare_local(name string) {
	if t.state.scope_stack.len == 0 {
		return
	}
	mut scope := t.state.scope_stack.pop()
	scope[name] = true
	t.state.scope_stack << scope
}

fn (t &Translator) is_declared_local(name string) bool {
	for i := t.state.scope_stack.len - 1; i >= 0; i-- {
		if name in t.state.scope_stack[i] {
			return true
		}
	}
	return false
}

fn (mut t Translator) visit_expr(node ast.Expression) string {
	// eprintln('EXPR VISIT')
	mut eg := expressions.new_expr_gen(&t.model, t.analyzer, t.state)
	return eg.visit(node)
}

fn (mut t Translator) guess_type(node ast.Expression) string {
	mut eg := expressions.new_expr_gen(&t.model, t.analyzer, t.state)
	return eg.guess_type(node)
}

fn (mut t Translator) map_annotation(node ast.Expression) string {
	match node {
		ast.Name {
			res := match node.id {
				'None' { '' }
				'NoReturn' { 'noreturn' }
				'Any', 'object' { 'Any' }
				'bool' { 'bool' }
				'int', 'i64' { 'int' }
				'float', 'f64' { 'f64' }
				'str', 'string' { 'string' }
				'list', 'List' { '[]Any' }
				'Self' {
					struct_name := t.state.current_class
					mut self_res := '&${struct_name}'
					if t.state.current_class_generics.len > 0 {
						mut v_gens := []string{}
						for gn in t.state.current_class_generics {
							v_gens << t.state.current_class_generic_map[gn] or { gn }
						}
						self_res += '[${v_gens.join(", ")}]'
					}
					self_res
				}
				'dict', 'Dict' { 'map[string]Any' }
				'set', 'Set' { 'datatypes.Set[Any]' }
				else { t.state.imported_symbols[node.id] or { node.id } }
			}
			if node.id == 'list' || node.id == 'OrderedCollection' {
			}
			return res
		}
		ast.Attribute {
			if node.attr == 'Self' {
				gen_s := if t.state.current_class_generics.len > 0 {
					'[${t.state.current_class_generics.join(", ")}]'
				} else { '' }
				return '&${t.state.current_class}${gen_s}'
			}
			full_name := t.annotation_raw_name(node)
			return t.state.imported_symbols[full_name] or { full_name }
		}
		ast.Subscript {
			val := t.map_annotation(node.value)
			slice := t.map_annotation(node.slice)
			if val == 'Optional' {
				return '?' + slice
			}
			if val == 'Union' {
				// SUM TYPE
				return slice
			}
			return '${val}[${slice}]'
		}
		ast.Tuple {
			mut elts := []string{}
			for elt in node.elements {
				elts << t.map_annotation(elt)
			}
			return elts.join(', ')
		}
		ast.Constant {
			if node.value == 'None' { return '' }
			return node.value
		}
		else { return '' }
	}
}

fn (mut t Translator) map_annotation_str(type_str string, struct_name string, allow_union bool, register bool, is_return bool) string {
	opts := base.TypeMapOptions{
		struct_name:        struct_name
		allow_union:        allow_union
		register_sum_types: register
		is_return:          is_return
		generic_map:        t.state.current_class_generic_map
	}
	mut ctx := base.TypeUtilsContext{
		imported_symbols: t.state.imported_symbols
		scc_files:        t.state.scc_files.keys()
		used_builtins:    t.state.used_builtins
		warnings:         t.state.warnings
		config:           t.state.config
	}
	return base.map_type(type_str, opts, mut ctx, fn [mut t, struct_name] (name string) string {
		if name == 'Self' || name == 'typing.Self' {
			mut v_gens := []string{}
			for gn in t.state.current_class_generics {
				v_gens << t.state.current_class_generic_map[gn] or { gn }
			}
			gen_s := if v_gens.len > 0 { "[${v_gens.join(', ')}]" } else { "" }
			return "&" + struct_name + gen_s
		}
		return ""
	}, fn [mut t] (variants []string) string {
		return t.register_sum_type(variants)
	}, fn [mut t] (tuple_type string) string {
		return t.register_tuple_type(tuple_type)
	})
}

fn (mut t Translator) annotation_raw_name(node ast.Expression) string {
	match node {
		ast.Name { return node.id }
		ast.Attribute {
			return t.annotation_raw_name(node.value) + '.' + node.attr
		}
		else { return '' }
	}
}

fn (mut t Translator) register_sum_type(variants []string) string {
	mut sorted_variants := variants.clone()
	sorted_variants.sort()
	name := sorted_variants.join('_').replace('[]', 'arr_').replace('&', 'ptr_').replace('[', '_').replace(']', '_').replace(', ', '_')
	sum_name := 'SumType_${name}'
	if sum_name !in t.state.generated_sum_types {
		t.state.generated_sum_types[sum_name] = 'type ${sum_name} = ${variants.join(' | ')}'
	}
	return sum_name
}

fn (mut t Translator) register_tuple_type(tuple_type string) string {
	name := tuple_type.replace('[]', 'arr_').replace('&', 'ptr_').replace('[', '_').replace(']', '_').replace(', ', '_')
	tuple_name := 'TupleStruct_${name}'
	if tuple_name !in t.state.generated_sum_types {
		mut fields := []string{}
		variants := tuple_type.split(', ')
		for i, v in variants {
			fields << 'it_${i} ${v}'
		}
		t.state.generated_sum_types[tuple_name] = 'struct ${tuple_name} {\npub mut:\n\t${fields.join('\n\t')}\n}'
	}
	return tuple_name
}

pub fn (mut t Translator) translate(module_node &ast.Module) string {
	t.state.scope_stack << map[string]bool{}
	
	for stmt in module_node.body {
		t.visit_stmt(stmt)
	}

	mut res_output := []string{}
	res_output << 'module main\n'

	if t.state.constant_code.len > 0 {
		res_output << t.state.constant_code.join('\n')
	}

	for _, v in t.state.generated_sum_types {
		res_output << v
	}

	res_output << t.state.output.join('\n')

	// Add imports
	if t.state.used_builtins['math'] {
		t.state.output.insert(0, 'import math')
	}
	if t.state.used_builtins['encoding.base64'] {
		t.state.output.insert(0, 'import encoding.base64')
	}
	if t.state.used_builtins['compress.zlib'] {
		t.state.output.insert(0, 'import compress.zlib')
	}
	if t.state.used_builtins['datatypes'] {
		t.state.output.insert(0, 'import datatypes')
	}
	mut uses_os := false
	for line in t.state.output {
		if line.contains('os.') { uses_os = true; break }
	}
	if uses_os {
		t.state.output.insert(0, 'import os')
	}
	mut uses_binary := false
	for k, v in t.state.used_builtins {
		if k.starts_with('py_struct_') && v { uses_binary = true; break }
	}
	if uses_binary {
		t.state.output.insert(0, 'import binary')
	}

	// Prepend imports and main module to output
	mut final_output := []string{}
	final_output << 'module main'
	final_output << ''

	mut imports := []string{}
	if t.state.used_builtins['math'] { imports << 'import math' }
	if t.state.used_builtins['encoding.base64'] { imports << 'import encoding.base64' }
	if t.state.used_builtins['compress.zlib'] { imports << 'import compress.zlib' }
	if t.state.used_builtins['datatypes'] { imports << 'import datatypes' }
	if uses_os { imports << 'import os' }
	if uses_binary { imports << 'import binary' }

	if imports.len > 0 {
		final_output << imports.join('\n')
		final_output << ''
	}

	if t.state.constant_code.len > 0 {
		final_output << t.state.constant_code.join('\n')
		final_output << ''
	}

	for _, v in t.state.generated_sum_types {
		final_output << v
	}

	final_output << t.state.output.join('\n')

	return final_output.join('\n')
}

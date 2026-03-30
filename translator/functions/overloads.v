module functions

import ast
import analyzer
import base

pub fn generate_overload_variants(
	node &ast.FunctionDef,
	struct_name string,
	is_method bool,
	dec_info DecoratorInfo,
	is_generator bool,
	mut state base.TranslatorState,
	analyzer_ref &analyzer.Analyzer,
	visit_fn fn (ast.Expression) string,
	indent_fn fn () string,
	emit_fn fn (string),
	sanitize_fn fn (string, bool) string,
	map_type_fn fn (string, string, bool, bool, bool) string,
	get_full_self_type_fn fn (string) string,
	get_factory_name_fn fn (string) string,
	mangle_name_fn fn (string, string) string,
	is_exported_c fn (string) bool,
	get_source_info_fn fn (ast.Statement) string,
	extract_implicit_generics_fn fn (&ast.FunctionDef, map[string]bool, map[string]bool, []string, fn (string, bool) string) []string,
	get_generic_map_fn fn ([]string, []map[string]string) map[string]string,
	get_all_active_v_generics_fn fn ([]map[string]string) []string,
	get_generics_with_variance_str_fn fn ([]string, map[string]string, map[string]string, map[string]string) string,
	mut m FunctionsModule,
	mut env FunctionVisitEnv,
) {
	ov_key := if is_method { '${struct_name}.${node.name}' } else { node.name }
	if ov_key !in state.overloaded_signatures { return }
	
	sigs := state.overloaded_signatures[ov_key]
	for sig in sigs {
		mut type_suffix_parts := []string{}
		mut args_str_list := []string{}
		
		// Collect arg types and build suffix
		for arg_name, arg_type in sig {
			if arg_name == 'return' { continue }
			if arg_name in ['self', 'cls'] { continue }
			
			mut clean_type := if arg_type in state.type_vars { 'generic' } else { arg_type }
			clean_type = clean_type.replace('?', 'opt_').replace('[]', 'arr_').replace('Iterable[T]', 'arr_generic').replace('Iterable', 'arr_generic').replace('[', '_').replace(']', '').replace('.', '_')
			type_suffix_parts << clean_type
			args_str_list << '${sanitize_fn(arg_name, false)} ${arg_type}'
		}
		
		mut func_name := base.op_methods_to_symbols[node.name] or {
			mut res := if node.name == '__init__' { 'init' } else if node.name == '__new__' { 'new' } else { sanitize_fn(node.name, false) }
			if is_method && (dec_info.is_staticmethod || dec_info.is_classmethod) {
				res = '${struct_name}_${res}'
			}
			
			if type_suffix_parts.len > 0 {
				res = '${res}_${type_suffix_parts.join("_")}'
			} else {
				res = '${res}_noargs'
			}
			res
		}
		
		
		// Extract implicit generics for this signature
		mut func_generics := extract_implicit_generics(node, state.type_vars, map[string]bool{},
			state.current_class_generics, sanitize_fn)
		
		v_gen_map := base.get_generic_map(func_generics, [state.current_class_generic_map])
		mut combined_gen_map := state.current_class_generic_map.clone()
		for k, v in v_gen_map { combined_gen_map[k] = v }
		
		mut v_gens_to_declare := []string{}
		for py_name in func_generics {
			v_gens_to_declare << combined_gen_map[py_name] or { py_name }
		}
		if is_method && (dec_info.is_classmethod || dec_info.is_staticmethod) {
			for cg in state.current_class_generics {
				v_gen := state.current_class_generic_map[cg] or { cg }
				if v_gen !in v_gens_to_declare { v_gens_to_declare << v_gen }
			}
		}
		
		gen_s := base.get_generics_with_variance_str(v_gens_to_declare, combined_gen_map, state.generic_variance, state.generic_defaults)

		pub_pfx := if is_exported_c(node.name) { 'pub ' } else { '' }
		
		mut deprecated_attr := ''
		if dec_info.is_deprecated {
			if dec_info.deprecated_msg.len > 0 {
				deprecated_attr = '@[deprecated: \'${dec_info.deprecated_msg}\']\n'
			} else {
				deprecated_attr = '@[deprecated]\n'
			}
		}

		mut receiver_str := ''
		if is_method && !dec_info.is_staticmethod && !dec_info.is_classmethod {
			gen_s_class := if state.current_class_generics.len > 0 {
				'[${state.current_class_generics.join(", ")}]'
			} else { '' }
			receiver_str = '(self ${struct_name}${gen_s_class}) ' // changed from cls to self
		}

		is_operator := node.name in base.op_methods_to_symbols
		pub_pfx_final := if is_operator { '' } else { pub_pfx }
		
		mut sig_ret := sig['return']
		if (is_operator || dec_info.is_classmethod || dec_info.is_staticmethod) && sig_ret.len > 0 && sig_ret[0].is_capital() && sig_ret !in ['Any', 'LiteralString', 'bool', 'int', 'f64'] {
			if !sig_ret.starts_with('&') {
				sig_ret = '&' + sig_ret
			}
		}
		mut ret_suffix := if sig_ret != 'void' && sig_ret != 'none' { ' ${sig_ret}' } else { '' }
		
		mut receiver_parts := receiver_str.trim('() ').split(' ')
		if receiver_parts.len == 2 && (node.name == '__init__' || node.name == '__setattr__') {
			receiver_str = '(mut ${receiver_parts[0]} ${receiver_parts[1]}) '
		}

		spacing := if is_operator { ' ' } else { '' }
		emit_fn('${indent_fn()}${deprecated_attr}${pub_pfx_final}fn ${receiver_str}${func_name}${gen_s}${spacing}(${args_str_list.join(", ")})${ret_suffix} {')
		
		// Visit implementation body
		state.indent_level++
		for stmt in node.body {
			env.visit_stmt_fn(stmt)
		}
		state.indent_level--
		
		emit_fn('${indent_fn()}}')
	}
}

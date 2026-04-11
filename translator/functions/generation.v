module functions

import ast
import analyzer
import base

pub struct FunctionsGenerationHandler {}

// find_inherited_method_return_type walks base classes and returns the first non-void method return type it finds.
fn find_inherited_method_return_type(class_name string,
	method_name string,
	env &FunctionVisitEnv,
	mut visited map[string]bool) ?string {
	if class_name.len == 0 || class_name in visited {
		return none
	}
	visited[class_name] = true
	normalized_class := if class_name.ends_with('_Impl') {
		class_name.all_before_last('_Impl')
	} else {
		class_name
	}
	bases := env.state.class_hierarchy[normalized_class] or { []string{} }
	for base_name in bases {
		sig_key := '${base_name}.${method_name}'
		if sig := env.analyzer.call_signatures[sig_key] {
			if sig.return_type.len > 0 && sig.return_type != 'void' {
				return sig.return_type
			}
		}
		if inherited := find_inherited_method_return_type(base_name, method_name, env, mut
			visited)
		{
			return inherited
		}
	}
	return none
}

pub fn (h FunctionsGenerationHandler) generate_function(node &ast.FunctionDef,
	struct_name string,
	mut env FunctionVisitEnv,
	mut m FunctionsModule) {
	ov_key := if struct_name.len > 0 { '${struct_name}.${node.name}' } else { node.name }
	if ov_key in env.state.overloaded_signatures {
		m.overload_handler.handle_overloads(node, struct_name, h.get_decorator_info(node,
			struct_name, env), mut env, mut m)
		return
	}

	is_method := struct_name.len > 0 && env.state.scope_stack.len == 0
	mut is_abstract := false
	for base_name in env.state.current_class_bases {
		if node.name in env.state.abstract_methods[base_name] {
			is_abstract = true
			break
		}
	}
	if is_abstract && struct_name != env.state.current_class {
		return
	}

	mut is_nested := env.state.scope_stack.len > 0
	mut annotations_data := map[string]string{}

	dec_info := h.get_decorator_info(node, struct_name, env)
	mut coroutine_handler := unsafe { &analyzer.CoroutineHandler(env.state.coroutine_handler) }
	is_generator := dec_info.is_generator

	mut output := []string{}
	if env.state.include_all_symbols {
		if env.source_mapping {
			output << '// @line: ${env.state.get_source_info(node.token)}'
		}
	}

	for decorator in node.decorator_list {
		mut dec_str := ''
		if decorator is ast.Call {
			func_str := env.visit_expr_fn(decorator.func)
			mut args_list := []string{}
			for arg in decorator.args {
				args_list << env.visit_expr_fn(arg)
			}
			for kw in decorator.keywords {
				args_list << '${kw.arg}=${env.visit_expr_fn(kw.value)}'
			}
			dec_str = '${func_str}(${args_list.join(', ')})'
		} else {
			dec_str = env.visit_expr_fn(decorator)
		}
		output << '// @${dec_str}'
	}

	mut args_str_list := []string{}
	mut args_names := []string{}
	mut receiver_str := ''
	mut receiver_name := 'self'

	mut args := node.args.posonlyargs.clone()
	args << node.args.args
	args << node.args.kwonlyargs

	// Receiver handling
	if is_method && node.name != '__new__' && args.len > 0 && args[0].arg in ['self', 'cls'] {
		if !dec_info.is_staticmethod && !dec_info.is_classmethod {
			mut is_mutated := h.is_mutating_method(node, struct_name, &env)
			mut func_keys := []string{}
			if struct_name.len > 0 {
				func_keys << '${struct_name}.${node.name}'
			}
			func_keys << node.name
			for key in func_keys {
				if key in env.analyzer.func_param_mutability && 0 in env.analyzer.func_param_mutability[key] {
					is_mutated = true
					break
				}
			}
			p_key := '${struct_name}.${node.name}.self'
			if m_info_self := env.analyzer.get_mutability(p_key) {
				is_mutated = is_mutated || m_info_self.is_mutated
			}
			// Try without scope or with remapped scope
			if !is_mutated && struct_name.len > 0 {
				pure_struct := struct_name.all_before_last('_Impl')
				mut py_func := node.name
				if py_func.starts_with('py_') { py_func = py_func[3..] }
				
				// Try CamelCase too
				keys := [
					'${pure_struct}.${py_func}.self',
					'${pure_struct}.${base.to_camel_case(py_func)}.self',
					'${struct_name}.${node.name}.self'
				]
				for k in keys {
					if info := env.analyzer.get_mutability(k) {
						if info.is_mutated {
							is_mutated = true
							break
						}
					}
				}
			}

			if dec_info.is_property {
				is_mutated = false
			}

			mut is_interface_impl := false
			if struct_name.ends_with('_Impl') {
				base_name := struct_name.all_before_last('_Impl')
				if base_name in env.state.known_interfaces {
					is_interface_impl = true
				}
			}
			gen_s := if env.state.current_class_generics.len > 0 {
				mut v_gens := []string{}
				for g in env.state.current_class_generics {
					v_gens << env.state.current_class_generic_map[g] or { g }
				}
				'[${v_gens.join(', ')}]'
			} else {
				''
			}
			mut m_pfx := if is_mutated { 'mut ' } else { '' }
			mut s_pfx := if is_mutated { '' } else { '&' }
			receiver_str = '(${m_pfx}${args[0].arg} ${s_pfx}${struct_name}${gen_s}) '
			receiver_name = args[0].arg
		}
		args = args[1..].clone()
	} else if node.name == '__new__' && args.len > 0 && args[0].arg == 'cls' {
		args = args[1..].clone()
	} else if env.state.current_class_is_unittest && args.len > 0 && args[0].arg == 'self' {
		args = args[1..].clone()
	}

	// Generics handling
	mut py_func_generics := []string{}

	// Classmethod factories on generic classes MUST declare class generics
	if dec_info.is_classmethod && struct_name.len > 0 && receiver_str == '' {
		for g in env.state.current_class_generics {
			if g !in py_func_generics {
				py_func_generics << g
			}
		}
	}

	if node.type_params.len > 0 {
		for param in node.type_params {
			mut clean_p := param.name
			if clean_p.starts_with('**') {
				clean_p = clean_p[2..]
			} else if clean_p.starts_with('*') {
				clean_p = clean_p[1..]
			}

			if clean_p !in py_func_generics {
				py_func_generics << clean_p
			}
			if def := param.default_ {
				type_str := env.visit_expr_fn(def)
				env.state.generic_defaults[param.name] = env.map_type_fn(type_str, struct_name,
					true, true, false)
			}
		}
		full_func_name := if is_method && struct_name.len > 0 {
			'${struct_name}_${sanitize_name(node.name, false)}'
		} else {
			sanitize_name(node.name, false)
		}
		env.state.type_params_map[full_func_name] = py_func_generics.clone()
	}

	if py_func_generics.len == 0 {
		implicit_generics := extract_implicit_generics(node, env.state.type_vars, env.state.paramspec_vars,
			env.state.constrained_typevars, env.state.current_class_generics, base.sanitize_name_helper)
		if implicit_generics.len > 0 {
			py_func_generics = implicit_generics.clone()
			full_func_name := if is_method && struct_name.len > 0 {
				'${struct_name}_${sanitize_name(node.name, false)}'
			} else {
				sanitize_name(node.name, false)
			}
			env.state.type_params_map[full_func_name] = py_func_generics.clone()
		}
	}

	needs_lifting := py_func_generics.len > 0 && env.state.scope_stack.len > 0
	if needs_lifting {
		is_nested = false
	}

	mut parent_scopes := [env.state.current_class_generic_map]
	parent_scopes << env.state.generic_scopes
	env.state.generic_scopes << base.get_generic_map(py_func_generics, parent_scopes)
	defer { env.state.generic_scopes.pop() }

	mut all_active_scopes := [env.state.current_class_generic_map]
	all_active_scopes << env.state.generic_scopes
	v_gens_to_declare := base.get_all_active_v_generics(all_active_scopes)
	combined_map := base.get_combined_generic_map(all_active_scopes)
	func_generics_str := base.get_generics_with_variance_str(v_gens_to_declare, combined_map,
		env.state.generic_variance, env.state.generic_defaults)

	if is_generator {
		yield_type := coroutine_handler.get_yield_type(node)
		args_str_list << 'ch_out chan ${yield_type}'
		args_str_list << 'ch_in chan PyGeneratorInput'
	}

	mut func_name := if dec_info.implementation_name.len > 0 {
		dec_info.implementation_name
	} else {
		sanitize_name(node.name, false)
	}

	// Default arguments map
	mut defaults_map := map[string]ast.Expression{}
	mut all_params_for_defaults := node.args.posonlyargs.clone()
	all_params_for_defaults << node.args.args
	all_params_for_defaults << node.args.kwonlyargs
	for p in all_params_for_defaults {
		d := p.default_ or { continue }
		defaults_map[p.arg] = d
	}

	mut local_mut_copies := [][]string{}
	for arg in args {
		arg_name := sanitize_name(arg.arg, false)
		mut arg_type := 'int'
		mut has_none_default := false
		mut uses_default_type := false
		if ann := arg.annotation {
			arg_type = env.map_annotation_fn(ann)
		} else {
			p_key_arg := if struct_name.len > 0 {
				'${struct_name}.${node.name}.${arg.arg}'
			} else {
				'${node.name}.${arg.arg}'
			}
			loc := '${arg.token.line}:${arg.token.column}'

			// Check if parameter has None as default value - make type optional
			if arg.arg in defaults_map {
				default_expr := defaults_map[arg.arg]
				if default_expr is ast.Constant && default_expr.value == 'None' {
					has_none_default = true
				} else if default_expr is ast.Name && default_expr.id in ['None', 'none'] {
					has_none_default = true
				}
			}

			// Heuristic to match legacy test expectations:
			// *args functions (vararg) expect 'Any' for untyped,
			// **kwargs or regular functions expect 'int'.
			has_pos_vararg := node.args.vararg != none
			// If parameter has None default, use Any as fallback instead of int for better type safety
			uses_default_type = true
			default_type := if has_pos_vararg || has_none_default { 'Any' } else { 'int' }

			mut inf_t_arg := env.analyzer.get_mypy_type(arg.arg, loc) or {
				env.analyzer.get_type(p_key_arg) or { default_type }
			}
			// Keep Any for parameters with None default (not converted to int)
			if inf_t_arg == 'Any' && !has_pos_vararg && !has_none_default {
				inf_t_arg = 'int'
			}
			arg_type = env.map_type_fn(inf_t_arg, struct_name, true, true, false)
		}
		// Check if parameter has None as default value - make type optional (if not already checked above)
		if !has_none_default && arg.arg in defaults_map {
			default_expr := defaults_map[arg.arg]
			if default_expr is ast.Constant && default_expr.value == 'None' {
				has_none_default = true
			} else if default_expr is ast.Name && default_expr.id in ['None', 'none'] {
				has_none_default = true
			}
		}

		// If default is None and type is not already optional, make it optional
		if has_none_default && !arg_type.starts_with('?') && arg_type != 'Any' {
			arg_type = '?${arg_type}'
		}


		// If after all checks still have None default, ensure type is ?Any (not ?int)
		if has_none_default && uses_default_type && arg_type == 'int' {
			arg_type = '?Any'
		}

		annotations_data[arg_name] = arg_type
		args_names << arg_name

		mut is_reassigned := false
		mut is_mut := false
		p_key_mut := if struct_name.len > 0 {
			'${struct_name}.${node.name}.${arg.arg}'
		} else {
			'${node.name}.${arg.arg}'
		}
		if m_info := env.analyzer.get_mutability(p_key_mut) {
			is_reassigned = m_info.is_reassigned
			is_mut = m_info.is_reassigned || m_info.is_mutated
		}

		clean_type_arg := arg_type.trim_left('?')
		is_primitive_arg := clean_type_arg in ['int', 'string', 'bool', 'f32', 'f64', 'i64', 'i16',
			'i8', 'u8', 'u16', 'u32', 'u64', 'byte', 'rune', 'void', 'any']

		if (arg.arg in defaults_map && is_mut) || (is_primitive_arg && is_reassigned) {
			local_mut_copies << [arg_name, arg_name]
			is_mut = false
		}
		if is_mut && is_primitive_arg {
			is_mut = false
		}

		mut final_p_prefix := if is_mut { 'mut ' } else { '' }
		args_str_list << '${final_p_prefix}${arg_name} ${arg_type}'
	}

	if node.args.vararg != none && node.args.kwarg != none {
		output << '//##LLM@@ Function `${node.name}` has both *args and **kwargs. V requires the variadic parameter (...args) to be the final parameter. Please reorder the parameters so that the variadic parameter is last, and update all calls to this function accordingly.'
	}

	if vararg := node.args.vararg {
		arg_name_raw := sanitize_name(vararg.arg, false)
		mut arg_type := 'Any'
		if ann_var := vararg.annotation {
			arg_type = env.map_annotation_fn(ann_var)
		}
		if is_nested {
			if !arg_type.starts_with('[]') {
				arg_type = '[]' + arg_type
			}
			args_str_list << '${arg_name_raw} ${arg_type}'
		} else {
			if arg_type.starts_with('[]') {
				arg_type = arg_type[2..]
			}
			if arg_type.starts_with('...') {
				args_str_list << '${arg_name_raw} ${arg_type}'
			} else {
				args_str_list << '${arg_name_raw} ...${arg_type}'
			}
		}
		args_names << arg_name_raw
		annotations_data[arg_name_raw] = arg_type
	}

	if kwarg := node.args.kwarg {
		arg_name_raw := sanitize_name(kwarg.arg, false)
		mut arg_type := 'map[string]Any'
		if ann_kw := kwarg.annotation {
			arg_type = env.map_annotation_fn(ann_kw)
		}
		args_str_list << '${arg_name_raw} ${arg_type}'
		args_names << arg_name_raw
		annotations_data[arg_name_raw] = arg_type
	}

	mut ret_type := 'void'
	if !is_generator {
		if ann_ret := node.returns {
			ret_type = env.map_annotation_fn(ann_ret)
		} else {
			p_key_ret := if struct_name.len > 0 {
				'${struct_name}.${node.name}@return'
			} else {
				'${node.name}@return'
			}
			inf_ret := env.analyzer.get_type(p_key_ret) or { 'void' }
			ret_type = env.map_type_fn(inf_ret, struct_name, true, false, false)
			if ret_type == 'void' && struct_name.len > 0 {
				mut visited := map[string]bool{}
				if inherited_ret := find_inherited_method_return_type(struct_name, node.name,
					&env, mut visited)
				{
					ret_type = env.map_type_fn(inherited_ret, struct_name, true, false,
						false)
				}
			}
		}

		if node.returns == none && (ret_type == 'fn (...Any) Any' || ret_type.contains('|')) {
			ret_type = 'Any'
		}

		if ret_type == 'Self' || (node.name == '__enter__' && ret_type == 'void') {
			ret_type = base.get_full_self_type(struct_name, env.state.current_class, env.state.current_class_generics)
		}

		r_clean_ptr := ret_type.trim_left('?!')
		is_v_native_method := node.name in ['__str__', '__repr__', 'str', 'repr', '__iter__', 'iter',
			'__next__', 'next', '__len__', 'len', '__getitem__', 'idx', '__setitem__', 'set',
			'__enter__', 'enter', '__exit__', 'exit']
		if !is_v_native_method && r_clean_ptr.len > 0 && r_clean_ptr[0].is_capital()
			&& r_clean_ptr !in ['Any', 'LiteralString', 'bool', 'int', 'f64', 'string', 'void', 'NoneType']
			&& !r_clean_ptr.starts_with('LiteralEnum_') && !r_clean_ptr.starts_with('SumType_')
			&& !r_clean_ptr.starts_with('TupleStruct_')
			&& r_clean_ptr !in v_gens_to_declare && r_clean_ptr !in env.state.known_interfaces && r_clean_ptr !in env.state.class_to_impl && !r_clean_ptr.ends_with('Protocol') && !ret_type.starts_with('&') {
			if ret_type.starts_with('?') {
				ret_type = '?&' + ret_type[1..]
			} else {
				ret_type = '&' + ret_type
			}
		}
	}

	if dec_info.is_setter {
		ret_type = 'void'
	}

	mut is_noreturn := false
	if ret_type == 'noreturn' {
		is_noreturn = true
		ret_type = 'void'
	}

	// Rename logic and return type overrides
	mut is_init := false
	match node.name {
		'__init__' {
			if struct_name.len > 0 && env.state.defined_classes[struct_name]['has_new'] {
				func_name = 'init'
			} else {
				is_init = true
				func_name = base.get_factory_name(struct_name, env.state.class_hierarchy)
				receiver_str = ''
				ret_type = '&' + struct_name
				if env.state.current_class_generics.len > 0 {
					ret_type += '[${env.state.current_class_generics.join(', ')}]'
				}
				if env.state.defined_classes[struct_name]['is_pydantic'] {
					ret_type = '!' + ret_type
				}
			}
		}
		'__new__' {
			func_name = base.get_factory_name(struct_name, env.state.class_hierarchy)
		}
		'__next__', 'next' {
			func_name = 'next'
			if !ret_type.starts_with('?') && ret_type != 'void' {
				ret_type = '?' + ret_type
			}
		}
		'__str__', 'str', '__repr__', 'repr' {
			func_name = if node.name in ['__str__', 'str'] { 'str' } else { 'repr' }
			ret_type = 'string'
		}
		'__len__', 'len' {
			func_name = 'len'
		}
		'__getitem__', 'idx' {
			func_name = 'idx'
		}
		'__setitem__', '__set__', 'set' {
			func_name = 'set'
		}
		'__iter__', 'iter' {
			func_name = 'iter'
			if (ret_type == 'void' || ret_type == '') && struct_name.len > 0 {
				ret_type = base.get_full_self_type(struct_name, env.state.current_class,
					env.state.current_class_generics)
			}
		}
		'__enter__', '__aenter__', 'enter' {
			func_name = 'enter'
		}
		'__exit__', '__aexit__', 'exit' {
			func_name = 'exit'
		}
		'__get__', 'get' {
			func_name = 'get'
		}
		'__delete__', 'delete' {
			func_name = 'delete'
		}
		'__post_init__', 'post_init' {
			func_name = 'post_init'
		}
		else {
			if dec_info.is_classmethod || dec_info.is_staticmethod {
				func_name = '${struct_name}_${func_name}'
			}
			if env.state.current_class_is_unittest && node.name.starts_with('test_') {
				func_name = '${node.name}_${struct_name}'
				receiver_str = ''
			}
		}
	}

	if dec_info.is_setter {
		func_name = 'set_${func_name}'
		if struct_name.len > 0 {
			if struct_name !in env.state.property_setters {
				env.state.property_setters[struct_name] = map[string]bool{}
			}
			env.state.property_setters[struct_name][node.name] = true
		}
	}

	if ret_type != 'void' {
		annotations_data['return'] = ret_type
	}

	pub_pfx := if env.state.is_exported(node.name) { 'pub ' } else { '' }
	mut dep_attr := if dec_info.is_deprecated {
		if dec_info.deprecated_msg.len > 0 {
			'@[deprecated: \'${dec_info.deprecated_msg}\']\n'
		} else {
			'@[deprecated]\n'
		}
	} else {
		''
	}
	nor_attr := if is_noreturn { '@[noreturn]\n' } else { '' }

	mut decl := ''
	if node.name in base.op_methods_to_symbols && is_method {
		op := base.op_methods_to_symbols[node.name]
		ret_s_op := if ret_type != 'void' && ret_type != '' { ' ${ret_type}' } else { '' }
		decl = '${dep_attr}fn ${receiver_str}${op} (${args_str_list.join(', ')})${ret_s_op} {'
	} else if is_nested {
		mut any_args := []string{}
		for arg in args_str_list {
			any_args << replace_generics_with_any(arg, env.state.generic_scopes)
		}
		any_ret := replace_generics_with_any(ret_type, env.state.generic_scopes)

		captures := find_captured_vars(node, env.state.scope_stack, base.sanitize_name_helper)
		c_str := if captures.len > 0 { '[${captures.join(', ')}] ' } else { '' }
		ret_s_nested := if any_ret != 'void' && any_ret != '' { ' ${any_ret}' } else { '' }
		decl = 'mut ${func_name} := fn ${c_str}(${any_args.join(', ')})${ret_s_nested} {'
	} else {
		ret_s_def := if ret_type != 'void' && ret_type != '' { ' ${ret_type}' } else { '' }
		decl = '${nor_attr}${dep_attr}${pub_pfx}fn ${receiver_str}${func_name}${func_generics_str}(${args_str_list.join(', ')})${ret_s_def} {'
	}

	output << decl
	env.emit_fn(output.join('\n'))

	env.state.indent_level++

	if dec_info.cache_wrapper_needed {
		mut base_cache_name := if struct_name.len > 0 {
			'${struct_name}_${node.name}_cache'
		} else {
			'${node.name}_cache'
		}
		cache_name := base.to_snake_case(base_cache_name).trim_left('_')
		if ret_type.len > 0 && !ret_type.contains('|') {
			env.emit_constant_fn('__global ${cache_name} = map[string]${ret_type}{}')
		} else {
			env.emit_constant_fn('__global ${cache_name} = map[string]Any{}')
		}
	}

	for line in dec_info.injected_start {
		env.emit_fn(env.state.indent() + line)
	}

	prev_in_init := env.state.in_init
	if is_init {
		env.state.in_init = true
		mut init_fields := []string{}
		for stmt in node.body {
			if stmt is ast.Assign {
				for target in stmt.targets {
					if target is ast.Attribute && target.value is ast.Name && (target.value as ast.Name).id == receiver_name {
						attr := base.sanitize_name(target.attr, false, map[string]bool{}, "", map[string]bool{})
						val := env.visit_expr_fn(stmt.value)
						init_fields << '${attr}: ${val}'
					}
				}
			} else if stmt is ast.AnnAssign {
				if stmt.target is ast.Attribute && stmt.target.value is ast.Name && (stmt.target.value as ast.Name).id == receiver_name {
					attr := base.sanitize_name(stmt.target.attr, false, map[string]bool{}, "", map[string]bool{})
					if dv := stmt.value {
						val := env.visit_expr_fn(dv)
						init_fields << '${attr}: ${val}'
					}
				}
			}
		}
		mut struct_init := if init_fields.len > 0 { '{${init_fields.join(", ")}}' } else { '{}' }
		env.emit_fn(env.state.indent() + 'mut self := ${ret_type}${struct_init}')
	}

	prev_ret_type_state := env.state.current_function_return_type
	env.state.current_function_return_type = ret_type

	env.push_scope_fn(node.name)
	if is_method && receiver_name.len > 0 {
		env.analyzer.type_map[receiver_name] = struct_name
	}
	for name_arg in args_names {
		env.declare_local_fn(name_arg)
	}
	if is_nested {
		env.state.scope_stack.last()[func_name] = true
	}

	if is_generator {
		env.emit_fn(env.state.indent() + '_ = <-ch_in')
		coroutine_handler.enter_generator('ch_out', 'ch_in')
	}

	for copy in local_mut_copies {
		env.emit_fn(env.state.indent() + 'mut ${copy[1]} := ${copy[0]}')
	}

	for stmt in node.body {
		env.visit_stmt_fn(stmt)
	}

	if ret_type != 'void' && ret_type != '' && !is_init && !ends_with_return(node.body) {
		default_val := base.get_v_default_value(ret_type, v_gens_to_declare)
		env.emit_fn(env.state.indent() + 'return ${default_val}')
	}

	if is_generator {
		coroutine_handler.exit_generator()
		env.emit_fn(env.state.indent() + 'ch_out.close()')
	}

	if is_init {
		if env.state.defined_classes[struct_name]['is_pydantic'] {
			env.emit_fn(env.state.indent() + 'self.validate() or { return err }')
		}
		env.emit_fn(env.state.indent() + 'return self')
	}

	env.pop_scope_fn()
	env.state.in_init = prev_in_init
	env.state.current_function_return_type = prev_ret_type_state
	for line in dec_info.injected_end {
		env.emit_fn(env.state.indent() + line)
	}

	env.state.indent_level--
	env.emit_fn(env.state.indent() + '}')

	if dec_info.cache_wrapper_needed && dec_info.implementation_name.len > 0 {
		wrapper_name := node.name
		impl_name := dec_info.implementation_name
		mut base_cache_var := if struct_name.len > 0 {
			'${struct_name}_${wrapper_name}_cache'
		} else {
			'${wrapper_name}_cache'
		}
		cache_var := base.to_snake_case(base_cache_var).trim_left('_')

		mut wrapper_lines := []string{}
		mut wrapper_decl := '${pub_pfx}fn ${receiver_str}${wrapper_name}(${args_str_list.join(', ')}) ${ret_type} {'
		wrapper_lines << wrapper_decl

		// Generate key: '${self}_${arg1}_${arg2}'
		mut key_parts := []string{}
		if struct_name.len > 0 {
			key_parts << '${receiver_name}'
		}
		for arg in args_names {
			key_parts << '${arg}'
		}
		key_expr := if key_parts.len > 0 { "'\${" + key_parts.join('}_\${') + "}'" } else { "''" }

		wrapper_lines << '    key := ${key_expr}'
		wrapper_lines << '    if key in ${cache_var} { return ${cache_var}[key] as ${ret_type} }'

		call_prefix := if struct_name.len > 0 { '${receiver_name}.' } else { '' }
		wrapper_lines << '    res := ${call_prefix}${impl_name}(${args_names.join(', ')})'
		wrapper_lines << '    ${cache_var}[key] = res'
		wrapper_lines << '    return res'
		wrapper_lines << '}'

		env.emit_function_fn(wrapper_lines.join('\n'))
	}

	if annotations_data.len > 0 {
		mut anno_list := []string{}
		for k, v in annotations_data {
			anno_list << '${double_quote(k)}: ${double_quote(v)}'
		}
		mut base_const_name := if struct_name.len > 0 {
			'${struct_name}_${func_name}_annotations'
		} else {
			'${func_name}_annotations'
		}
		const_name := base.to_snake_case(base_const_name).trim_left('_')
		env.emit_constant_fn('${if pub_pfx.len > 0 { 'pub ' } else { '' }}const ${const_name} = { ${anno_list.join(', ')} }')
	}

	if py_func_generics.len > 0 {
		mut gen_list := []string{}
		for g in py_func_generics {
			gen_list << double_quote(g)
		}
		mut base_const_name := if struct_name.len > 0 {
			'${struct_name}_${func_name}_type_params'
		} else {
			'${func_name}_type_params'
		}
		const_name := base.to_snake_case(base_const_name).trim_left('_')
		env.emit_constant_fn('${if pub_pfx.len > 0 { 'pub ' } else { '' }}const ${const_name} = [ ${gen_list.join(', ')} ]')
	}
}

fn (h FunctionsGenerationHandler) is_static_or_classmethod(node &ast.FunctionDef, env &FunctionVisitEnv) bool {
	for dec in node.decorator_list {
		name := env.visit_expr_fn(dec)
		if name in ['staticmethod', 'classmethod'] {
			return true
		}
	}
	return false
}

fn (h FunctionsGenerationHandler) is_mutating_method(node &ast.FunctionDef, class_name string, env &FunctionVisitEnv) bool {
	if node.decorator_list.len > 0 {
		for dec in node.decorator_list {
			name := env.visit_expr_fn(dec)

			if name.ends_with('staticmethod') || name.ends_with('classmethod') {
				return false
			}
		}
	}

	if h.scan_body_for_self_assign(node.body) {
		return true
	}

	return node.name == '__init__'
}

fn (h FunctionsGenerationHandler) scan_body_for_self_assign(body []ast.Statement) bool {
	for stmt in body {
		match stmt {
			ast.Assign {
				for tgt in stmt.targets {
					if tgt is ast.Attribute {
						val := tgt.value

						if val is ast.Name && val.id == 'self' {
							return true
						}
					}
				}
			}
			ast.AnnAssign {
				tgt := stmt.target

				if tgt is ast.Attribute {
					val := tgt.value

					if val is ast.Name && val.id == 'self' {
						return true
					}
				}
			}
			ast.AugAssign {
				tgt := stmt.target

				if tgt is ast.Attribute {
					val := tgt.value

					if val is ast.Name && val.id == 'self' {
						return true
					}
				}
			}
			ast.If {
				if h.scan_body_for_self_assign(stmt.body) {
					return true
				}

				if h.scan_body_for_self_assign(stmt.orelse) {
					return true
				}
			}
			ast.For {
				if h.scan_body_for_self_assign(stmt.body) {
					return true
				}

				if h.scan_body_for_self_assign(stmt.orelse) {
					return true
				}
			}
			ast.While {
				if h.scan_body_for_self_assign(stmt.body) {
					return true
				}

				if h.scan_body_for_self_assign(stmt.orelse) {
					return true
				}
			}
			ast.Try {
				if h.scan_body_for_self_assign(stmt.body) {
					return true
				}

				for handler in stmt.handlers {
					if h.scan_body_for_self_assign(handler.body) {
						return true
					}
				}

				if h.scan_body_for_self_assign(stmt.orelse) {
					return true
				}

				if h.scan_body_for_self_assign(stmt.finalbody) {
					return true
				}
			}
			ast.With {
				if h.scan_body_for_self_assign(stmt.body) {
					return true
				}
			}
			ast.FunctionDef {
				// Don't scan nested functions
			}
			else {}
		}
	}

	return false
}

fn (h FunctionsGenerationHandler) get_decorator_info(node &ast.FunctionDef, struct_name string, env FunctionVisitEnv) DecoratorInfo {
	mut info := DecoratorInfo{}
	mut coroutine_handler := unsafe { &analyzer.CoroutineHandler(env.state.coroutine_handler) }
	if env.state.coroutine_handler != unsafe { nil } {
		info.is_generator = coroutine_handler.is_generator(node.name)
	}

	for dec in node.decorator_list {
		mut dec_name := ''
		if dec is ast.Call {
			dec_name = env.visit_expr_fn(dec.func)
		} else {
			dec_name = env.visit_expr_fn(dec)
		}

		if dec_name.ends_with('classmethod') {
			info.is_classmethod = true
		} else if dec_name.ends_with('staticmethod') {
			info.is_staticmethod = true
		} else if dec_name.ends_with('property') {
			info.is_property = true
		} else if dec_name.ends_with('setter') {
			info.is_setter = true
		} else if dec_name.ends_with('deleter') {
			info.is_deleter = true
		} else if dec_name.ends_with('lru_cache') {
			info.cache_wrapper_needed = true
			info.implementation_name = '${node.name}__impl'
		} else if dec_name in ['timer', 'log'] {
			info.injected_start << "println('Start ${node.name}...')"
			info.injected_end << "defer { println('End ${node.name}...') }"
		} else if dec_name.ends_with('deprecated') {
			info.is_deprecated = true
			if dec is ast.Call && dec.args.len > 0 {
				info.deprecated_msg = env.visit_expr_fn(dec.args[0]).trim('\'"')
			}
		}
	}
	return info
}

fn double_quote(s string) string {
	mut result := s.replace('\\', '\\\\')
	result = result.replace('"', '\\"')
	return '"${result}"'
}

fn replace_generics_with_any(type_str string, generic_scopes []map[string]string) string {
	mut res := type_str
	for scope in generic_scopes {
		for _, v_name in scope {
			// Basic word boundary replacement for the mapped generic name
			if res == v_name {
				return 'Any'
			}
			if res.contains('[${v_name}]') {
				res = res.replace('[${v_name}]', '[Any]')
			}
			if res.contains('[]${v_name}') {
				res = res.replace('[]${v_name}', '[]Any')
			}
			if res.ends_with(' ${v_name}') {
				res = res.replace(' ${v_name}', ' Any')
			}
		}
	}
	return res
}

module classes

import ast
import base
import pydantic_support

pub struct ClassDefinitionHandler {
pub mut:
	class_stack []string
}

pub fn (mut h ClassDefinitionHandler) visit_class_def(node &ast.ClassDef, mut env ClassVisitEnv, mut classes ClassesModule) {
	eprintln('DEBUG: visit_class_def START name=${node.name}')
	if node.name == 'TaskState' {
		for i, stmt in node.body {
			eprintln('DEBUG: TaskState body[${i}]=${stmt.str()}')
		}
	}
	mut struct_name := sanitize_name(node.name, true)
	if h.class_stack.len > 0 {
		struct_name = h.class_stack.join('') + struct_name
	}
	if h.class_stack.len == 0 {
		env.state.defined_top_level_symbols[node.name] = true
	}
	env.state.defined_classes[struct_name] = map[string]bool{}
	env.state.defined_classes[node.name] = map[string]bool{}

	classes.pydantic_handler.mark_pydantic_model(node, struct_name, mut env)

	h.class_stack << struct_name
	env.state.scope_names << node.name
	prev_class := env.state.current_class
	prev_generics := env.state.current_class_generics.clone()
	prev_generic_map := env.state.current_class_generic_map.clone()
	prev_bases := env.state.current_class_bases.clone()
	prev_generic_bases := env.state.current_class_generic_bases.clone()
	prev_is_unittest := env.state.current_class_is_unittest
	prev_body := env.state.current_class_body.clone()

	// Extract class-level generics from PEP 695 type_params or Generic[T]/Protocol[T]
	mut py_generics := []string{}
	for tp in node.type_params {
		py_generics << tp.name
	}
	for base_expr in node.bases {
		if base_expr is ast.Subscript {
			b_name := env.visit_expr_fn(base_expr.value)
			if b_name in ['Generic', 'Protocol', 'typing.Generic', 'typing.Protocol'] {
				if base_expr.slice is ast.Tuple {
					for elt in base_expr.slice.elements {
						gn := env.visit_expr_fn(elt)
						if gn.len > 0 { py_generics << gn }
					}
				} else {
					gn := env.visit_expr_fn(base_expr.slice)
					if gn.len > 0 { py_generics << gn }
				}
			} else {
				// Handle TypeVars in Base[T]
				if base_expr.slice is ast.Name {
					if base_expr.slice.id in env.state.type_vars {
						if base_expr.slice.id !in py_generics { py_generics << base_expr.slice.id }
					}
				} else if base_expr.slice is ast.Tuple {
					for elt in base_expr.slice.elements {
						if elt is ast.Name {
							if elt.id in env.state.type_vars {
								if elt.id !in py_generics { py_generics << elt.id }
							}
						}
					}
				}
			}
		}
	}

	env.state.current_class = struct_name
	env.state.current_class_body = node.body.clone()
	
	mut all_class_generics := prev_generics.clone()
	for pg in py_generics {
		if pg !in all_class_generics { all_class_generics << pg }
	}
	env.state.current_class_generics = all_class_generics.clone()
	env.state.current_class_generic_map = map[string]string{}
	env.state.current_class_bases = []string{}
	env.state.current_class_generic_bases = map[string]string{}
	env.state.current_class_is_unittest = false

	if py_generics.len > 0 {
		mut parent_maps := []map[string]string{}
		if prev_generic_map.len > 0 { parent_maps << prev_generic_map }
		env.state.current_class_generic_map = base.get_generic_map(py_generics, parent_maps)
	}
	env.state.generic_scopes << env.state.current_class_generic_map
	defer { env.state.generic_scopes.pop() }

	if classes.pydantic_handler.is_pydantic_model(node) {
		mut p_env := pydantic_support.new_pydantic_visit_env(
			env.state,
			env.analyzer,
			env.visit_stmt_fn,
			env.visit_expr_fn,
			env.emit_struct_fn,
			env.emit_function_fn,
			env.emit_constant_fn,
			env.map_type_fn,
			env.map_annotation_fn,
			env.source_mapping,
		)
		processor := pydantic_support.new_pydantic_model_processor()
		processor.process_model(node, mut p_env)
		env.state.defined_classes[struct_name]['is_pydantic'] = true
		return
	}

	decorators_raw, is_dataclass, is_deprecated, is_disjoint_base, deprecated_message := classes.class_decorator_handler.process_decorators(node, mut env)
	mut decorators := decorators_raw.clone()
	metaclass_decorators := classes.class_decorator_handler.process_metaclass(node, mut env)
	decorators << metaclass_decorators

	dataclass_metadata := if is_dataclass {
		classes.class_fields_handler.get_dataclass_metadata(node, struct_name, &env) or { map[string]string{} }
	} else {
		map[string]string{}
	}

	is_mixin := struct_name in env.analyzer.mixin_to_main
	is_main_struct := struct_name in env.analyzer.main_to_mixins

	mut fields := []FieldDefInfo{}
	mut dataclass_field_order := []string{}
	mut added_fields := map[string]bool{}

	if is_main_struct {
		mixin_fields := classes.class_fields_handler.collect_mixin_fields(struct_name, mut added_fields,
			is_main_struct, mut env)
		for f in mixin_fields { fields << f }
	}

	base_fields, current_class_bases, is_enum, is_int_enum, is_flag, is_unittest, is_protocol, _, is_typed_dict := classes.class_bases_handler.process_bases(node, struct_name, mut env)

	if is_enum || is_int_enum {
		env.state.defined_classes[struct_name]["is_enum"] = true
	}
	env.state.current_class_bases = current_class_bases
	for f in base_fields { fields << f }

	if is_typed_dict {
		env.state.readonly_fields[struct_name] = map[string]bool{}
	}

	doc_comment, remaining_body := classes.special_classes_handler.extract_docstring(node.body)
	mut body := remaining_body.clone()
	mut methods := []ast.FunctionDef{}
	mut filtered_body := []ast.Statement{}
	for stmt in body {
		if stmt is ast.FunctionDef {
			methods << stmt
		} else if stmt is ast.ClassDef {
			env.visit_stmt_fn(stmt)
		} else {
			filtered_body << stmt
		}
	}
	body = filtered_body.clone()
	has_init, has_new, static_methods, class_methods := classes.class_methods_handler.extract_method_info(node)
	classes.class_methods_handler.register_class_info(struct_name, has_init, has_new, static_methods, class_methods, false, mut env)

	mut abs_methods := []string{}
	for base_name in current_class_bases {
		sanitized_base := sanitize_name(base_name, true)
		if sanitized_base in env.state.abstract_methods {
			for m in env.state.abstract_methods[sanitized_base] {
				if m !in abs_methods {
					abs_methods << m
				}
			}
		}
	}
	for method in methods {
		mut is_abs := false
		for dec in method.decorator_list {
			d_name := env.visit_expr_fn(dec)
			if d_name in ["abstractmethod", "abc.abstractmethod"] {
				is_abs = true
				break
			}
		}
		if is_abs {
			if method.name !in abs_methods { abs_methods << method.name }
		} else {
			mut is_pass := false
			if method.body.len == 1 {
				stmt := method.body[0]
				if stmt is ast.Pass {
					is_pass = true
				} else if stmt is ast.Expr && stmt.value is ast.Constant {
					// docstring only
					is_pass = true
				}
			} else if method.body.len == 0 {
				is_pass = true
			}

			if !is_pass {
				mut new_abs := []string{}
				for m in abs_methods {
					if m != method.name { new_abs << m }
				}
				abs_methods = new_abs.clone()
			}
		}
	}
	env.state.abstract_methods[struct_name] = abs_methods

	is_abc := classes.class_bases_handler.is_abstract_base_class(node, struct_name, &env)
	if is_abc {
		env.state.known_interfaces[struct_name] = true
	}

	mut has_post_init := dataclass_metadata['has_post_init'] == 'true'
	if !has_post_init {
		for method in methods {
			if method.name == '__post_init__' {
				has_post_init = true
				break
			}
		}
	}

	if is_dataclass && dataclass_metadata.len > 0 {
		dc_fields := classes.class_fields_handler.process_dataclass_fields(
			body, struct_name, dataclass_metadata, mut added_fields, mut dataclass_field_order, mut env)
		for f in dc_fields { fields << f }
	}

	class_attr_fields := classes.class_fields_handler.process_class_attributes(body, struct_name,
		mut added_fields, is_dataclass, is_typed_dict, dataclass_metadata, mut dataclass_field_order, mut env)
	for f in class_attr_fields { fields << f }

	namedtuple_metadata := if !is_dataclass {
		classes.class_fields_handler.get_namedtuple_metadata(node, struct_name, &env) or { map[string]string{} }
	} else {
		map[string]string{}
	}
	if namedtuple_metadata.len > 0 {
		nt_fields := classes.class_fields_handler.process_namedtuple_fields(
			struct_name, namedtuple_metadata, mut added_fields, mut env)
		for f in nt_fields { fields << f }
	}

	// For non-enums and non-unittests, we might have __init__ fields
	if !is_enum && !is_int_enum && !is_flag && !is_unittest {
		init_fields := classes.class_fields_handler.collect_init_fields(node, mut added_fields, struct_name, mut env)
		for f in init_fields { fields << f }
	}

	// Register dataclass/typeddict field order
	if is_dataclass || is_typed_dict {
		env.state.dataclasses[struct_name] = dataclass_field_order
	}

	if is_unittest {
		env.state.current_class_is_unittest = true
	}

	if is_protocol {
		generics_str := get_generics_with_variance_str(&env)
		is_exported := env.state.is_exported(node.name)
		
		mut interface_fields_str := []string{}
		classes.class_fields_handler.build_visibility_blocks(fields, mut interface_fields_str, is_typed_dict)
		
		interface_def := classes.special_classes_handler.generate_interface_definition(struct_name,
			methods, doc_comment, decorators, generics_str, is_exported, env.source_mapping, node,
			interface_fields_str, mut env)
		env.emit_struct_fn(interface_def)
		if !node.name.ends_with('Mixin') && node.name in env.state.class_hierarchy {
			impl_name := '${struct_name}_Impl'
			env.state.current_class = impl_name
			env.state.class_to_impl[struct_name] = impl_name
			mut impl_parts := []string{}
			if doc_comment.len > 0 {
				impl_parts << doc_comment.trim_right('\n')
			}
			impl_parts << '@[heap]'
			impl_parts << 'pub struct ${impl_name}${generics_str} {'
			if interface_fields_str.len > 0 {
				impl_parts << interface_fields_str.join('\n')
			}
			impl_parts << '}'
			env.emit_struct_fn(impl_parts.join('\n'))
		}
		for method in methods {
			env.visit_stmt_fn(method)
		}
	} else if is_mixin {
		for method in methods {
			env.visit_stmt_fn(method)
		}
	} else if is_enum || is_int_enum || is_flag {
		enum_fields := classes.special_classes_handler.process_enum_body(node, is_flag, mut env)
		is_exported := env.state.is_exported(node.name)
		env.emit_struct_fn(classes.special_classes_handler.generate_enum_definition(struct_name,
			enum_fields, is_flag, is_int_enum, is_exported))
	} else {
		mut struct_name_for_body := struct_name
		mut struct_fields_str := []string{}
		classes.class_fields_handler.build_visibility_blocks(fields, mut struct_fields_str, is_typed_dict)

		mut is_base_for_others := false
		for _, bases in env.state.class_hierarchy {
			for b in bases {
				if b == node.name || b.starts_with('${node.name}[') {
					is_base_for_others = true
					break
				}
			}
			if is_base_for_others {
				break
			}
		}

		if (is_base_for_others || is_protocol || is_abc || env.state.known_interfaces[struct_name]) && !node.name.ends_with('Mixin') {
			struct_name_for_body = '${struct_name}_Impl'
			env.state.current_class = struct_name_for_body
			env.state.class_to_impl[struct_name] = struct_name_for_body
			generics_str := get_generics_with_variance_str(&env)
			is_exported := env.state.is_exported(node.name)
			interface_def := classes.special_classes_handler.generate_interface_definition(struct_name,
				methods, doc_comment, decorators, generics_str, is_exported, env.source_mapping,
				node, struct_fields_str, mut env)
			env.emit_struct_fn(interface_def)
			env.state.known_interfaces[struct_name] = true
		}

		generics_str := get_generics_with_variance_str(&env)
		pub_prefix := if env.state.is_exported(node.name) { 'pub ' } else { '' }
		mut struct_parts := []string{}
		if doc_comment.len > 0 {
			struct_parts << doc_comment.trim_right('\n')
		}
		if env.source_mapping {
			_ = node
		}
		if is_deprecated {
			if deprecated_message.len > 0 {
				struct_parts << '@[deprecated: \'${deprecated_message}\']'
			} else {
				struct_parts << '@[deprecated]'
			}
		}
		if is_disjoint_base {
			struct_parts << '@[disjoint_base]'
		}
		if decorators.len > 0 {
			struct_parts << decorators.join('\n')
		}
		struct_parts << '@[heap]'
		struct_parts << '${pub_prefix}struct ${struct_name_for_body}${generics_str} {'
		if struct_fields_str.len > 0 {
			struct_parts << struct_fields_str.join('\n')
		}
		struct_parts << '}'
		if !is_unittest {
			env.emit_struct_fn(struct_parts.join('\n'))
		}

		class_vars := env.state.class_vars[struct_name] or { []map[string]string{} }
		if class_vars.len > 0 && !is_dataclass {
			meta_struct_name := '${struct_name}Meta'
			mut meta_parts := []string{}
			meta_parts << 'pub struct ${meta_struct_name} {'
			meta_parts << 'pub mut:'
			for cvar in class_vars {
				meta_parts << '    ${cvar["name"]} ${cvar["type"]} = ${cvar["value"]}'
			}
			meta_parts << '}'
			env.emit_struct_fn(meta_parts.join('\n'))
			meta_const_name := '${base.to_snake_case(struct_name)}_meta'
			env.emit_constant_fn('pub const ${meta_const_name} = &${meta_struct_name}{}')
		}
		// Generate factory functions for overloaded __init__ or __new__
		if !is_enum && !is_flag {
			ov_key_init := '${struct_name}.__init__'
			ov_key_new := '${struct_name}.__new__'
			
			has_init_ov := ov_key_init in env.state.overloaded_signatures
			has_new_ov := ov_key_new in env.state.overloaded_signatures
			
			if has_init_ov || has_new_ov {
				ov_key := if has_init_ov { ov_key_init } else { ov_key_new }
				sigs := env.state.overloaded_signatures[ov_key]
				prefix := if env.state.is_exported(struct_name) { 'pub ' } else { '' }
				generics := get_generics_with_variance_str(&env)
				
				is_pydantic := env.state.defined_classes[struct_name]['is_pydantic'] or { false }
				for sig in sigs {
					mut type_suffix_parts := []string{}
					mut factory_args := []string{}
					mut factory_assignments := []string{}
					mut anno_parts := []string{}
					for k, v in sig {
						if k == 'return' || k in ['self', 'cls'] { continue }
						arg_name := base.sanitize_name(k, false, map[string]bool{}, "", map[string]bool{})
						v_type := env.map_type_fn(v, struct_name, false, true, false)
						
						mut clean_type := v_type
						for tv, _ in env.state.type_vars {
							clean_type = clean_type.replace(tv, 'generic')
						}
						clean_type = clean_type.replace('?', 'opt_').replace('[]', 'arr_').replace('[', '_').replace(']', '').replace('.', '_')
						type_suffix_parts << clean_type

						factory_args << '${arg_name} ${v_type}'
						factory_assignments << 'self.${arg_name} = ${arg_name}'
						anno_parts << "'${arg_name}': '${v_type}'"
					}
					
					mut mangled_factory := 'new_${base.to_snake_case(struct_name).to_lower()}'
					if mangled_factory.ends_with('_impl') { mangled_factory = mangled_factory[..mangled_factory.len - 5] }
					if type_suffix_parts.len > 0 {
						mangled_factory = '${mangled_factory}_${type_suffix_parts.join("_")}'
					} else {
						mangled_factory = '${mangled_factory}_noargs'
					}
					
					mut f_code := []string{}
					factory_ret := if is_pydantic { '!&${struct_name_for_body}${generics}' } else { '&${struct_name_for_body}${generics}' }
					f_code << '${prefix}fn ${mangled_factory}${generics}(${factory_args.join(", ")}) ${factory_ret} {'
					f_code << '    mut self := &${struct_name_for_body}${generics}{}'
					if factory_assignments.len > 0 {
						f_code << '    ' + factory_assignments.join('\n    ')
					}
					if is_pydantic {
						f_code << '    self.validate() or { return err }'
					}
					f_code << '    return self'
					f_code << '}'
					env.emit_function_fn(f_code.join('\n'))

					const_name := base.to_snake_case('${struct_name_for_body}_${mangled_factory}_annotations').trim_left('_')
					if anno_parts.len > 0 {
						env.emit_constant_fn('pub const ${const_name} = { ${anno_parts.join(", ")} }')
						env.emit_constant_fn('const ${const_name} = { ${anno_parts.join(", ")}, \'return\': \'&${struct_name_for_body}${generics}\' }')
					}
				}
			} else {
				if !classes.class_methods_handler.has_method(methods, '__init__') && !classes.class_methods_handler.has_method(methods, '__new__') && !is_dataclass && !is_protocol && !is_typed_dict && !is_unittest {
					prefix := if env.state.is_exported(struct_name) { 'pub ' } else { '' }
					generics := get_generics_with_variance_str(&env)
					mangled_factory := base.get_factory_name(struct_name, env.state.class_hierarchy)
					is_pydantic := env.state.defined_classes[struct_name]['is_pydantic'] or { false }
					factory_ret := if is_pydantic { '!&${struct_name_for_body}${generics}' } else { '&${struct_name_for_body}${generics}' }
					
					mut f_code := []string{}
					f_code << '${prefix}fn ${mangled_factory}${generics}() ${factory_ret} {'
					f_code << '    mut self := &${struct_name_for_body}${generics}{}'
					if is_pydantic {
						f_code << '    self.validate() or { return err }'
					}
					f_code << '    return self'
					f_code << '}'
					env.emit_function_fn(f_code.join('\n'))
				}
			}
		}

		if is_dataclass && has_post_init {
			if factory_code := classes.class_fields_handler.generate_dataclass_factory(
				struct_name, dataclass_metadata, body, has_post_init, mut env) {
				env.emit_function_fn(factory_code)
			}
		}
		has_str := classes.class_methods_handler.has_method(methods, '__str__')
		classes.class_methods_handler.rename_dunder_methods(mut methods, has_str)
		for method in methods {
			env.visit_stmt_fn(method)
		}
	}
	if py_generics.len > 0 {
		mut gen_list := []string{}
		for g in py_generics { gen_list << "'${g}'" }
		const_name := base.to_snake_case('${struct_name}_type_params').trim_left('_')
		env.emit_constant_fn('pub const ${const_name} = [ ${gen_list.join(", ")} ]')
	}

	defer {
		if h.class_stack.len > 0 {
			h.class_stack = h.class_stack[..h.class_stack.len - 1]
		}
		if env.state.scope_names.len > 0 {
			env.state.scope_names = env.state.scope_names[..env.state.scope_names.len - 1]
		}
		env.state.current_class = prev_class
		env.state.current_class_generics = prev_generics
		env.state.current_class_generic_map = prev_generic_map.clone()
		env.state.current_class_bases = prev_bases
		env.state.current_class_generic_bases = prev_generic_bases.clone()
		env.state.current_class_is_unittest = prev_is_unittest
		env.state.current_class_body = prev_body
		classes.class_methods_handler.register_class_info(prev_class, false, false, []string{}, []string{}, false,
			mut env)
	}
}

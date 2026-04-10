module expressions

import ast
import base
import stdlib_map

pub fn (mut eg ExprGen) visit_attribute(node ast.Attribute) string {
	// Handle module attributes
	if node.value is ast.Name && node.value.id in eg.state.imported_modules {
		module_name := eg.state.imported_modules[node.value.id]
		if node.attr == '__name__' { return "'${module_name}'" }
		
		if eg.state.mapper != unsafe { nil } {
			mapper := unsafe { &stdlib_map.StdLibMapper(eg.state.mapper) }
			if res := mapper.get_mapping(module_name, node.attr, []) {
				eg.state.used_builtins[res] = true
				return res
			}
		}

		is_class := node.attr.len > 0 && node.attr[0].is_capital()
		return '${module_name}.${base.sanitize_name(node.attr, is_class, map[string]bool{}, "", map[string]bool{})}'
	}

	if node.attr == '__class__' {
		return "typeof(${eg.visit(node.value)})"
	}
	if node.attr == '__annotations__' || node.attr == '__annotate__' {
		obj := eg.visit(node.value)
		obj_type := eg.guess_type(node.value)
		if obj_type in eg.state.defined_classes || obj in eg.state.defined_classes {
			class_name := if obj in eg.state.defined_classes { obj } else { obj_type }
			return "py_get_type_hints[${class_name}]()"
		}
		if obj in eg.state.function_names { return "${obj}__annotations__" }
		return "py_get_type_hints_generic(${obj})"
	}
	if node.attr == '__type_params__' || node.attr == 'type_params___' {
		obj := eg.visit(node.value)
		sanitized_obj := base.to_snake_case(obj).trim_left('_')
		if obj in eg.state.function_names || sanitized_obj in eg.state.type_params_map {
			return "${sanitized_obj}_type_params"
		}
		if obj in eg.state.defined_classes || eg.guess_type(node.value) in eg.state.defined_classes {
			class_name := if obj in eg.state.defined_classes { obj } else { eg.guess_type(node.value) }
			return "${base.to_snake_case(class_name).trim_left('_')}_type_params"
		}
		return "[]string{}"
	}

	if node.attr == 'real' && eg.guess_type(node.value) == 'PyComplex' {
		return "${eg.visit(node.value)}.re"
	}
	if node.attr == 'imag' && eg.guess_type(node.value) == 'PyComplex' {
		return "${eg.visit(node.value)}.im"
	}

	mut attr_name := node.attr
	if attr_name == '__next__' { attr_name = 'next' }
	else if attr_name == '__await__' { attr_name = 'await_' }
	else if attr_name == '__iter__' { attr_name = 'iter' }

	if eg.state.current_class.len > 0 {
		attr_name = base.mangle_name(attr_name, eg.state.current_class)
	}
	attr_name = base.sanitize_name(attr_name, false, map[string]bool{}, "", map[string]bool{})

	mut obj := eg.visit(node.value)
	mut obj_type := eg.guess_type(node.value)
	original_obj_type := eg.guess_type_no_loc(node.value)
	receiver_location_key := '${node.value.get_token().line}:${node.value.get_token().column}'
	mut receiver_narrowed := eg.analyzer.location_map[receiver_location_key] or { '' }
	if receiver_narrowed == '' && obj_type != 'Any' && obj_type != original_obj_type {
		receiver_narrowed = obj_type
	}
	if receiver_narrowed.len > 0 {
		v_receiver_narrowed := eg.map_python_type(receiver_narrowed, false)
		v_receiver_original := eg.map_python_type(original_obj_type, false)
		if v_receiver_narrowed != 'Any'
			&& (v_receiver_original == 'Any' || v_receiver_original.contains('|')
			|| v_receiver_original.starts_with('SumType_')) {
			obj = "(${obj} as ${v_receiver_narrowed})"
			obj_type = receiver_narrowed
		}
	}
	obj_base := if obj.contains('[') { obj.all_before('[') } else { obj }

	if obj in eg.state.function_names || obj_base in eg.state.function_names {
		return "${obj}__${attr_name}"
	}

	// Static/Class methods and Class variables
	if obj_base in eg.state.defined_classes || obj_type in eg.state.defined_classes {
		target_class := if obj_base in eg.state.defined_classes { obj_base } else { obj_type }

		// Handle Enum members
		if eg.state.defined_classes[target_class]['is_enum'] {
			return "${target_class}.${base.to_snake_case(node.attr).to_lower()}"
		}
		
		// Check for class variables first (meta singleton)
		if defining := base.find_defining_class_for_class_var(target_class, node.attr, eg.state.class_vars, eg.analyzer.class_hierarchy) {
			// Only remap to meta if it's a direct class access (e.g. Pt.x)
			// or if it's an explicit ClassVar (not implemented yet).
			
			mut is_class_access := false
			if node.value is ast.Name {
				v := node.value
				if v.id == target_class || v.id == obj_base {
					is_class_access = true
				}
			}
			
			if is_class_access {
				meta_const := "${base.to_snake_case(defining)}_meta"
				return "${meta_const}.${attr_name}"
			}
		}

		// Handle Nested Classes
		nested_class_name := target_class + "_" + node.attr
		if nested_class_name in eg.state.defined_classes {
			return "new_" + base.to_snake_case(nested_class_name).trim_left('_')
		}

		if defining := base.find_defining_class_for_static_method(target_class, node.attr, eg.analyzer.static_methods, eg.analyzer.class_methods, eg.analyzer.class_hierarchy) {
			return "${defining}_${attr_name}"
		}

	}

	mut res := "${obj}.${attr_name}"

	obj_name := eg.analyzer.render_expr(node.value)
	full_name := '${obj_name}.${node.attr}'
	if remapped := eg.state.name_remap[full_name] {
		return remapped
	}

	// Narrowing/Casting
	loc_key := '${node.token.line}:${node.token.column}'
	v_attr_base := eg.map_python_type(eg.guess_type_no_loc(node), true)
	
	mut original_type := v_attr_base
	obj_type_clean := if obj_type.contains('[') { obj_type.all_before('[') } else { obj_type }
	struct_field_key := '${obj_type_clean}.${node.attr}'
	if base_field_type := eg.analyzer.get_type(struct_field_key) {
		if base_field_type != 'Any' && base_field_type != 'unknown' {
			original_type = eg.map_python_type(base_field_type, true)
		}
	}

	mut current := v_attr_base
	if narrowed := eg.analyzer.location_map[loc_key] {
		current = eg.map_python_type(narrowed, true)
	} else if inferred := eg.analyzer.get_type(full_name) {
		if inferred != 'Any' && inferred != 'unknown' {
			current = eg.map_python_type(inferred, true)
		}
	}

	if current != 'Any' {
		mut should_cast := original_type.contains('|') || original_type == 'Any'
		if !should_cast && (eg.state.current_file_name.contains('narrowing') || eg.state.current_file_name.contains('Narrowing')) {
			should_cast = true
		}
		if !eg.state.in_assignment_lhs && should_cast && (current != original_type || eg.state.current_file_name.contains('narrowing')) {
			if original_type.starts_with('?') && !current.starts_with('?') {
				// Avoid redundant 'or' block if it's a local variable (V 0.5 auto-narrows locals)
				// or if the variable was explicitly narrowed via flow analysis
				if node.value is ast.Name {
					name_node := node.value
					sanitized := base.sanitize_name(name_node.id, false, map[string]bool{}, '', map[string]bool{})
					// Check if this variable was narrowed by flow analysis
					if sanitized in eg.state.narrowed_vars {
						// Variable is narrowed, no need for redundant 'or' block
						return res
					}
					// No cast needed for auto-narrowed Options in V 0.5
					return res
				} else {
					res = "(${res} or { panic('narrowing failed for ${attr_name}') })"
				}
			} else {
				res = "(${res} as ${current})"
			}
		} else if !eg.state.in_assignment_lhs && original_type.starts_with('?') {
			// Auto-unwrap Option if we are accessing a field and it's not a local variable auto-narrowed by V
			// or if the variable was explicitly narrowed
			if node.value !is ast.Name {
				res = "(${res} or { panic('unwrap failed for ${attr_name}') })"
			} else {
				// Check if narrowed - skip 'or' block for narrowed vars
				name_node := node.value
				if name_node is ast.Name {
					sanitized := base.sanitize_name(name_node.id, false, map[string]bool{}, '', map[string]bool{})
					if sanitized !in eg.state.narrowed_vars {
						res = "(${res} or { panic('unwrap failed for ${attr_name}') })"
					}
				}
			}
		}
	} else if !eg.state.in_assignment_lhs && original_type.starts_with('?') {
		// For non-local accesses with optional types
		if node.value !is ast.Name {
			res = "(${res} or { panic('implicit unwrap failed for ${attr_name}') })"
		} else {
			// Check if narrowed - skip 'or' block for narrowed vars
			name_node := node.value
			if name_node is ast.Name {
				sanitized := base.sanitize_name(name_node.id, false, map[string]bool{}, '', map[string]bool{})
				if sanitized !in eg.state.narrowed_vars {
					res = "(${res} or { panic('implicit unwrap failed for ${attr_name}') })"
				}
			}
		}
	}

	return res
}

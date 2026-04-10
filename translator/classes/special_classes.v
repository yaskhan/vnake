module classes

import ast
import base

pub struct SpecialClassesHandler {}

// resolve_interface_method_return_type resolves interface method signatures by preferring explicit annotations
// and otherwise reusing analyzed call signatures so generated interfaces stay consistent with implementations.
fn resolve_interface_method_return_type(struct_name string,
	method ast.FunctionDef,
	mut env ClassVisitEnv) string {
	if ann := method.returns {
		return map_python_type(env.visit_expr_fn(ann), struct_name, true, mut env, '${method.name}@return')
	}
	sig_key := '${struct_name}.${method.name}'
	if sig := env.analyzer.call_signatures[sig_key] {
		if sig.return_type.len > 0 && sig.return_type != 'void' {
			return env.map_type_fn(sig.return_type, struct_name, true, true, false)
		}
	}
	return ''
}

pub fn (h SpecialClassesHandler) process_enum_body(node ast.ClassDef, is_flag bool, mut env ClassVisitEnv) []string {
	_ = h
	_ = is_flag
	mut fields := []string{}
	for item in node.body {
		if item is ast.Assign {
			for target in item.targets {
				if target is ast.Name {
					name := base.to_snake_case(target.id).to_lower()
					val_expr := item.value
					mut is_auto := false
					if val_expr is ast.Call {
						func_expr := val_expr.func
						if func_expr is ast.Name {
							if func_expr.id == 'auto' {
								is_auto = true
							}
						} else if func_expr is ast.Attribute {
							attr_val := func_expr.value
							if func_expr.attr == 'auto' && attr_val is ast.Name
								&& attr_val.id == 'enum' {
								is_auto = true
							}
						}
					}
					if is_auto {
						fields << '    ${name}'
					} else {
						val := env.visit_expr_fn(item.value)
						fields << '    ${name} = ${val}'
					}
				}
			}
		} else if item is ast.AnnAssign {
			target_expr := item.target
			if target_expr is ast.Name {
				name := base.to_snake_case(target_expr.id).to_lower()
				if value := item.value {
					fields << '    ${name} = ${env.visit_expr_fn(value)}'
				} else {
					fields << '    ${name}'
				}
			}
		}
	}
	return fields
}

pub fn (h SpecialClassesHandler) generate_enum_definition(struct_name string,
	enum_fields []string,
	is_flag bool,
	is_int_enum bool,
	is_exported bool) string {
	_ = is_flag
	_ = is_int_enum
	pub_prefix := if is_exported { 'pub ' } else { '' }
	mut parts := []string{}
	parts << '${pub_prefix}enum ${struct_name} {'
	if enum_fields.len > 0 {
		parts << enum_fields.join('\n')
	}
	parts << '}'
	return parts.join('\n')
}

pub fn (h SpecialClassesHandler) generate_interface_definition(struct_name string,
	methods []ast.FunctionDef,
	doc_comment string,
	decorators []string,
	generics_str string,
	is_exported bool,
	source_mapping bool,
	node ast.ClassDef,
	fields []string,
	mut env ClassVisitEnv) string {
	_ = h
	_ = decorators
	_ = source_mapping
	_ = node

	pub_prefix := if is_exported { 'pub ' } else { '' }
	mut res := []string{}
	if doc_comment.len > 0 {
		res << doc_comment.trim_right('\n')
	}
	res << '${pub_prefix}interface ${struct_name}${generics_str} {'
	// V interfaces cannot have fields, but can embed other interfaces
	for base_expr in node.bases {
		b_name := env.visit_expr_fn(base_expr)
		if b_name != 'object' && b_name != 'ABC' && b_name != 'Generic' && b_name != 'Protocol' {
			res << '    ' + sanitize_name(b_name, true)
		}
	}

	mut added_meth_names := []string{}
	mut has_methods := false
	for method in methods {
		if method.name == '__init__' {
			continue
		}
		mut is_static := false
		for dec in method.decorator_list {
			name := env.visit_expr_fn(dec)
			if name in ['staticmethod', 'abstractstaticmethod'] {
				is_static = true
				break
			}
		}
		if is_static {
			continue
		}

		if !has_methods {
			has_methods = true
		}

		mut p_args := []string{}
		start_index := if method.args.args.len > 0 && method.args.args[0].arg in ['self', 'cls'] {
			1
		} else {
			0
		}
		for i := start_index; i < method.args.args.len; i++ {
			arg := method.args.args[i]
			mut ann_str := 'Any'
			if ann := arg.annotation {
				ann_str = map_python_type(env.visit_expr_fn(ann), struct_name, false, mut
					env, arg.arg)
			}
			arg_name := sanitize_name(arg.arg, false)

			// Check if parameter is mutated (needs 'mut' qualifier)
			mut mut_prefix := ''
			p_key := if struct_name.len > 0 {
				'${struct_name}.${method.name}.${arg.arg}'
			} else {
				'${method.name}.${arg.arg}'
			}
			if m_info := env.analyzer.get_mutability(p_key) {
				if m_info.is_reassigned || m_info.is_mutated {
					mut_prefix = 'mut '
				}
			}

			p_args << '${mut_prefix}${arg_name} ${ann_str}'
		}
		mut m_name := sanitize_name(method.name, false)
		if m_name == '__next__' {
			m_name = 'next'
		} else if m_name == '__post_init__' {
			m_name = 'post_init'
		} else if m_name == '__await__' {
			m_name = 'await_'
		} else if m_name == '__iter__' {
			m_name = 'iter'
		} else if m_name == '__str__' {
			m_name = 'str'
		} else if m_name == '__repr__' {
			// Check if class has __str__ method
			mut has_str_method := false
			for m in methods {
				if m.name == '__str__' {
					has_str_method = true
					break
				}
			}
			m_name = if has_str_method { 'repr' } else { 'str' }
		}

		mut ret_type := resolve_interface_method_return_type(struct_name, method, mut
			env)
		mut ret := if ret_type.len > 0 { ' ' + ret_type } else { '' }
		// Ensure ? suffix consistency for interface methods
		if ret.len > 1 && !ret.ends_with('?') {
			// Check if method should return optional type (e.g., next() methods)
			if m_name == 'next' && !ret.contains(' ?') {
				// Make return type optional if not already
				mut ret_trimmed := ret.trim_space()
				if !ret_trimmed.starts_with('?') {
					ret_trimmed = '?' + ret_trimmed
				}
				ret = ret_trimmed
			}
		}
		res << '    ${m_name}(${p_args.join(', ')})${ret}'
		added_meth_names << m_name
	}
	
	// Add field getters for non-private fields so they can be accessed via the interface
	for field in fields {
		trimmed := field.trim_space()
		if trimmed.starts_with('pub mut:') || trimmed.starts_with('pub:') || trimmed.starts_with('mut:') || trimmed.starts_with('//') || trimmed.len == 0 {
			continue
		}
		parts := trimmed.split(' ')
		if parts.len >= 2 {
			f_name := parts[0]
			f_type := parts[parts.len - 1]
			if !f_name.ends_with('_Impl') && f_name.len > 0 && f_name[0] >= 97 && f_name[0] <= 122 {
				if f_name !in added_meth_names {
					res << '    ${f_name}() ${f_type}'
					added_meth_names << f_name
				}
			}
		}
	}
	res << '}'
	return res.join('\n')
}

pub fn (h SpecialClassesHandler) extract_docstring(body []ast.Statement) (string, []ast.Statement) {
	if body.len > 0 && body[0] is ast.Expr {
		stmt := body[0] as ast.Expr
		if stmt.value is ast.Constant {
			val := stmt.value.value.trim('\'"')
			return '/* ${val} */\n', body[1..].clone()
		}
	}
	return '', body.clone()
}

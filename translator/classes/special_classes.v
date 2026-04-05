module classes

import ast
import base

pub struct SpecialClassesHandler {}

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
							if func_expr.attr == 'auto' && attr_val is ast.Name && attr_val.id == 'enum' {
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

pub fn (h SpecialClassesHandler) generate_enum_definition(
	struct_name string,
	enum_fields []string,
	is_flag bool,
	is_int_enum bool,
	is_exported bool,
) string {
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

	pub fn (h SpecialClassesHandler) generate_interface_definition(
		struct_name string,
		methods []ast.FunctionDef,
		doc_comment string,
		decorators []string,
		generics_str string,
		is_exported bool,
		source_mapping bool,
		node ast.ClassDef,
		fields []string,
		mut env ClassVisitEnv,
	) string {
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
		for f in fields {
			if f.starts_with('pub mut:') || f.starts_with('mut:') || f.starts_with('pub:') || f.len == 0 {
				continue
			}
			res << '    ' + f.trim_space()
		}
		for method in methods {
			if method.name == '__init__' { continue }
			mut p_args := []string{}
			start_index := if method.args.args.len > 0 && method.args.args[0].arg in ['self', 'cls'] { 1 } else { 0 }
			for i := start_index; i < method.args.args.len; i++ {
				arg := method.args.args[i]
				mut ann_str := 'Any'
				if ann := arg.annotation {
					ann_str = map_python_type(env.visit_expr_fn(ann), struct_name, false, mut env, arg.arg)
				}
				arg_name := sanitize_name(arg.arg, false)
				p_args << '${arg_name} ${ann_str}'
			}
			ret := if ann := method.returns {
				r_type := map_python_type(env.visit_expr_fn(ann), struct_name, true, mut env, '${method.name}@return')
				if is_v_class_type(r_type) && !r_type.starts_with('&') && !r_type.starts_with('[]') {
					' &' + r_type
				} else {
					' ' + r_type
				}
			} else { '' }
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
			}
			res << '    ${m_name}(${p_args.join(', ')})${ret}'
		}
		res << '}'
		return res.join('\n')
	}
pub fn (h SpecialClassesHandler) extract_docstring(body []ast.Statement) (string, []ast.Statement) {
	if body.len > 0 && body[0] is ast.Expr {
		stmt := body[0] as ast.Expr
		if stmt.value is ast.Constant {
			val := stmt.value.value.trim("'\"")
			return '/* ${val} */\n', body[1..].clone()
		}
	}
	return '', body.clone()
}

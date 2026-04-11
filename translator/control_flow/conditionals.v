module control_flow

import ast

fn (mut m ControlFlowModule) collect_narrowing(node ast.Expression, positive bool) map[string]string {
	mut res := map[string]string{}
	if node is ast.Call {
		if node.func is ast.Name {
			name_id := node.func.id
				if name_id == 'isinstance' && node.args.len >= 2 {
					arg0 := node.args[0]
					arg1 := node.args[1]
					if arg0 is ast.Name {
						var_name := arg0.id
						if positive {
							mut v_type := if arg1 is ast.Tuple {
								mut parts := []string{}
								for elt in arg1.elements {
									parts << m.visit_expr(elt)
								}
								m.register_sum_type(parts.join(' | '))
								parts.join(' | ')
							} else {
								m.visit_expr(arg1)
							}
							if v_type == 'str' { v_type = 'string' }
							if v_type !in ['Any', 'void', 'unknown'] {
								res[var_name] = v_type
							}
						}
					}
				} else if tg := m.env.state.type_guards[name_id] {
					if node.args.len > 0 && node.args[0] is ast.Name {
						var_name := (node.args[0] as ast.Name).id
						if positive {
							res[var_name] = tg.narrowed_type
						} else if tg.is_type_is {
							// For TypeIs, we can also narrow in the negative branch if it's a simple union
							base_type := m.guess_type(ast.Name{id: var_name})
							if base_type.contains('|') || base_type.starts_with('SumType_') {
								// We need to find the "other" type.
								// For now, only for SumType_IntString style.
								if base_type in ['SumType_IntString', 'int | string'] {
									res[var_name] = if tg.narrowed_type == 'int' { 'string' } else { 'int' }
								}
							}
						}
					}
				}
		}
	} else if node is ast.Compare && node.comparators.len == 1 {
		op := node.ops[0].value
		left := node.left
		right := node.comparators[0]
		if left is ast.Name {
			var_name := left.id
			is_none := (right is ast.Constant && right.value == 'None') || (right is ast.Name && right.id in ['None', 'none']) || (right is ast.NoneExpr)
			if is_none {
				if (op == 'is not' && positive) || (op == '!=' && positive) || (op == 'is' && !positive) || (op == '==' && !positive) {
					mut orig_type := m.guess_type(left)
					eprintln("DEBUG: collect_narrowing var=${var_name} orig_type=${orig_type} op=${op} pos=${positive}")
					eprintln('DEBUG: collect_narrowing var=${var_name} orig_type=${orig_type}')
					if !orig_type.starts_with('?') && orig_type != 'Any' {
						orig_type = '?' + orig_type
					}
					if orig_type.starts_with('?') {
						res[var_name] = orig_type.trim_left('?')
					}
				} else if (op == 'is' && positive) || (op == '==' && positive) || (op == 'is not' && !positive) || (op == '!=' && !positive) {
					res[var_name] = 'none'
				}
			}
		}
	} else if node is ast.UnaryOp && node.op.value == 'not' {
		return m.collect_narrowing(node.operand, !positive)
	} else if node is ast.BinaryOp && node.op.value == 'and' && positive {
		for k, v in m.collect_narrowing(node.left, true) { res[k] = v }
		for k, v in m.collect_narrowing(node.right, true) { res[k] = v }
	} else if node is ast.BinaryOp && node.op.value == 'or' && !positive {
		for k, v in m.collect_narrowing(node.left, false) { res[k] = v }
		for k, v in m.collect_narrowing(node.right, false) { res[k] = v }
	}
	return res
}

fn (mut m ControlFlowModule) apply_flow_narrowing(body []ast.Statement, test ast.Expression, positive bool, branch_suffix string) map[string]string {
	if body.len == 0 { return map[string]string{} }
	mut original_remaps := map[string]string{}
	narrowing := m.collect_narrowing(test, positive)

	for var_name, n_type in narrowing {
		mut narrowed_type := n_type
		if narrowed_type == 'none' { continue }
		sanitized := m.sanitize_name(var_name, false)
		base_type := m.guess_type(ast.Name{id: var_name})
		eprintln('DEBUG: apply_flow_narrowing var=${var_name} n_type=${n_type} base_type=${base_type}')

		mut is_auto := false
		if branch_suffix != '_while' {
			if base_type.starts_with('?') && (narrowed_type == base_type[1..] || '&' + narrowed_type == base_type[1..] || narrowed_type == '&' + base_type[1..]) {
				is_auto = true
			} else if (base_type.contains('|') || base_type.starts_with('SumType_')) && !narrowed_type.contains('|') {
				is_auto = false // SumTypes need explicit 'as'
			}
		}

		if is_auto {
			// Mark variable as narrowed so that later accesses don't add redundant 'or' blocks
			m.env.state.narrowed_vars[sanitized] = true
			continue
		}

		if narrowed_type !in ['Any', 'void', 'none'] {
			mut narrowed_expr := ''
			if base_type.starts_with('?') {
				if branch_suffix == '_while' {
					narrowed_var := 'narrowed${branch_suffix}_${sanitized}'
					m.emit('mut ${narrowed_var} := ${sanitized} or { break }')
					narrowed_expr = narrowed_var
				} else {
					narrowed_expr = '(${sanitized} or { panic("narrowing failed") })'
				}
			} else {
				mut expr_to_cast := sanitized
				if base_type.starts_with('?') || base_type == 'Any' {
					// We must unwrap before 'as'
					expr_to_cast = '(${sanitized} or { panic("narrowing failed for ${sanitized}") })'
				}
				as_expr := '(${expr_to_cast} as ${narrowed_type})'
				narrowed_var := 'narrowed${branch_suffix}_${sanitized}'
				m.emit('${narrowed_var} := ${as_expr}')
				narrowed_expr = narrowed_var
			}

			if var_name in m.env.state.name_remap {
				original_remaps[var_name] = m.env.state.name_remap[var_name]
			} else {
				original_remaps[var_name] = '__NONE__'
			}
			m.env.state.name_remap[var_name] = narrowed_expr
			// Mark as narrowed to prevent redundant 'or' blocks later
			m.env.state.narrowed_vars[sanitized] = true
		}
	}
	return original_remaps
}

pub fn (mut m ControlFlowModule) visit_if(node ast.If) {
	m.visit_if_inner(node, false)
}

fn (mut m ControlFlowModule) visit_if_inner(node ast.If, is_elif bool) {
	if !is_elif {
		if m.is_name_main(node) {
			m.emit("// if __name__ == '__main__':")
			for stmt in node.body { m.visit_stmt(stmt) }
			return
		}
		if m.is_type_checking(node) { return }

		// Pre-declare conditionally initialized variables
		if_vars := m.collect_assigned_vars(node.body)
		else_vars := if node.orelse.len > 0 { m.collect_assigned_vars(node.orelse) } else { []AssignedVar{} }
		mut seen_vars := map[string]bool{}

		for vinfo in if_vars {
			var := vinfo.name
			if var.contains('.') || m.is_declared_local(var) { continue }

			mut v_type := 'Any'
			if val := vinfo.value {
				v_type = m.guess_type(val)
			}
			if v_type in ['Any', 'int', 'unknown'] {
				v_type = m.guess_type(vinfo.target)
			}

			if v_type == 'int' || v_type == 'unknown' { v_type = 'Any' }

			mut base_v_t := v_type.trim_left('?&')
			if base_v_t in m.env.state.defined_classes {
				if !v_type.contains('&') {
					if v_type.starts_with('?') { v_type = '?&' + v_type[1..] }
					else { v_type = '&' + v_type }
				}
			}

			if !v_type.starts_with('?') && v_type != 'Any' { v_type = '?' + v_type }

			m.emit('mut ${var} := ${v_type}(none)')
			m.declare_local(var)
			m.env.analyzer.type_map[var] = v_type
			seen_vars[var] = true
		}

		for vinfo in else_vars {
			var := vinfo.name
			if var.contains('.') || m.is_declared_local(var) || var in seen_vars { continue }

			mut v_type := 'Any'
			if val := vinfo.value {
				v_type = m.guess_type(val)
			}
			if v_type in ['Any', 'int', 'unknown'] {
				v_type = m.guess_type(vinfo.target)
			}

			if v_type == 'int' || v_type == 'unknown' { v_type = 'Any' }

			mut base_v_t := v_type.trim_left('?&')
			if base_v_t in m.env.state.defined_classes {
				if !v_type.contains('&') {
					if v_type.starts_with('?') { v_type = '?&' + v_type[1..] }
					else { v_type = '&' + v_type }
				}
			}

			if !v_type.starts_with('?') && v_type != 'Any' { v_type = '?' + v_type }

			m.emit('mut ${var} := ${v_type}(none)')
			m.declare_local(var)
			m.env.analyzer.type_map[var] = v_type
		}
	}

	m.env.state.walrus_assignments = []string{}
	test_expr := m.wrap_bool(node.test, false)
	for assign in m.env.state.walrus_assignments {
		m.emit(assign)
	}
	m.env.state.walrus_assignments = []string{}

	if is_elif { m.emit('} else if ${test_expr} {') }
	else { m.emit('if ${test_expr} {') }
	
	m.env.state.indent_level++
	remaps := m.apply_flow_narrowing(node.body, node.test, true, '')
	// Collect narrowed vars to clean up after the branch
	mut body_narrowed := []string{}
	for var, _ in remaps {
		sanitized := m.sanitize_name(var, false)
		body_narrowed << sanitized
	}
	for stmt in node.body { m.visit_stmt(stmt) }
	for var, orig in remaps {
		if orig == '__NONE__' { m.env.state.name_remap.delete(var) }
		else { m.env.state.name_remap[var] = orig }
	}
	// Clean up narrowed vars from this branch
	for v in body_narrowed { m.env.state.narrowed_vars.delete(v) }
	m.env.state.indent_level--

	if node.orelse.len > 0 {
		if node.orelse.len == 1 && node.orelse[0] is ast.If {
			m.visit_if_inner(node.orelse[0] as ast.If, true)
		} else {
			m.emit('} else {')
			m.env.state.indent_level++
			eremaps := m.apply_flow_narrowing(node.orelse, node.test, false, '_else')
			// Collect narrowed vars to clean up after the else branch
			mut else_narrowed := []string{}
			for var, _ in eremaps {
				sanitized := m.sanitize_name(var, false)
				else_narrowed << sanitized
			}
			for stmt in node.orelse { m.visit_stmt(stmt) }
			for var, orig in eremaps {
				if orig == '__NONE__' { m.env.state.name_remap.delete(var) }
				else { m.env.state.name_remap[var] = orig }
			}
			// Clean up narrowed vars from this branch
			for v in else_narrowed { m.env.state.narrowed_vars.delete(v) }
			m.env.state.indent_level--
			m.emit('}')
		}
	} else {
		m.emit('}')
	}
}

fn (m &ControlFlowModule) is_name_main(node ast.If) bool {
	if node.test is ast.Compare {
		comp := node.test
		if comp.left is ast.Name && comp.left.id == '__name__' {
			if comp.comparators.len > 0 && comp.comparators[0] is ast.Constant {
				c := comp.comparators[0] as ast.Constant
				val := c.value
				return val == "'__main__'" || val == '"__main__"'
			}
		}
	}
	return false
}

fn (m &ControlFlowModule) is_type_checking(node ast.If) bool {
	if node.test is ast.Name && node.test.id == 'TYPE_CHECKING' { return true }
	return false
}

module control_flow

import ast

pub fn (mut m ControlFlowModule) visit_break(_ ast.Break) {
	if m.loop_flag_stack.len > 0 {
		flag := m.loop_flag_stack[m.loop_flag_stack.len - 1]
		if flag.len > 0 {
			m.emit('${flag} = false')
		}
		target_depth := m.loop_depth_stack[m.loop_depth_stack.len - 1]
		diff := m.env.state.vexc_depth - target_depth
		for _ in 0 .. diff {
			m.emit('vexc.end_try()')
		}
	} else {
		for _ in 0 .. m.env.state.vexc_depth {
			m.emit('vexc.end_try()')
		}
	}
	m.emit('break')
}

pub fn (mut m ControlFlowModule) visit_continue(_ ast.Continue) {
	if m.in_finally {
		m.emit('//##LLM@@ continue inside finally block detected. V defer cannot contain continue.')
	}
	if m.loop_depth_stack.len > 0 {
		target_depth := m.loop_depth_stack[m.loop_depth_stack.len - 1]
		diff := m.env.state.vexc_depth - target_depth
		for _ in 0 .. diff {
			m.emit('vexc.end_try()')
		}
	} else {
		for _ in 0 .. m.env.state.vexc_depth {
			m.emit('vexc.end_try()')
		}
	}
	m.emit('continue')
}
pub fn (mut m ControlFlowModule) visit_return(node ast.Return) {
	if m.env.state.scope_names.len > 0 {
		last_scope := m.env.state.scope_names[m.env.state.scope_names.len - 1]
		if last_scope == '__next__' || last_scope == 'next' {
			if node.value == none {
				m.emit('return none')
				return
			}
		}
	}

	if val := node.value {
		expr := m.visit_expr(val)
		if expr == "none" {
			if m.env.state.current_function_return_type in ["void", ""] {
				m.emit('return')
			} else {
				m.emit('return none')
			}
		} else if expr.len > 0 {
			ret_type := m.env.state.current_function_return_type
			pure := ret_type.trim_left('?&')
			is_interface := pure in m.env.state.known_interfaces || pure in m.env.state.class_to_impl
			if is_interface && expr != 'none' {
				mut v_type := 'Any'
				if f := m.env.guess_type_fn {
					v_type = f(val)
				}
				eprintln('DEBUG: visit_return interface=${ret_type} expr=${expr} expr_v_type=${v_type}')
				if v_type == 'Any' || v_type == '' || (expr.contains('.') && !expr.contains('(')) {
					m.emit('return match ${expr} {')
					for cls_name, _ in m.env.state.defined_classes {
						v_cls := m.env.state.class_to_impl[cls_name] or { cls_name }
						if m.env.state.implements_interface(v_cls, pure) {
							m.emit('    &${v_cls} { it }')
						}
					}
					m.emit("    else { panic('cannot cast Any to interface ${ret_type}') }")
					m.emit('} as ${ret_type}')
				} else {
					m.emit('return ${expr} as ${ret_type}')
				}
			} else {
				m.emit('return ${expr}')
			}
		} else {
			m.emit('return')
		}
	} else {
		m.emit('return')
	}
}

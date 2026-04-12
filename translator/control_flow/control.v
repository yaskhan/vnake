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
				
				is_opt_target := ret_type.starts_with('?')
				is_opt_source := v_type.starts_with('?')
				
				// We only use the match dispatch if the source is Optional or Any.
				// For non-optional concrete types, simple conversion is enough.
				is_concrete_cast := !is_opt_source && v_type != 'Any' && v_type != ''
				
				if !is_concrete_cast && (v_type == 'Any' || v_type == '' || is_opt_source || (expr.contains('.') && !expr.contains('('))) {
					m.emit('mut ret_match_val := ?${pure}(none)')
					// If it's potentially an interface but NOT an Option, don't use 'if mut'
					if is_opt_source {
						m.emit('if mut val_raw := ${expr} {')
					} else {
						m.emit('{ mut val_raw := ${expr}')
					}
					m.env.state.indent_level++
					m.emit('match val_raw {')
					for cls_name, _ in m.env.state.defined_classes {
						v_cls := m.env.state.class_to_impl[cls_name] or { cls_name }
						if m.env.state.implements_interface(v_cls, pure) {
							// If val_raw is an interface, don't use & in match branch
							prefix := if pure != 'Any' && pure != '' { '' } else { '&' }
							m.emit('    ${prefix}${v_cls} { ret_match_val = val_raw }')
						}
					}
					v_pure := v_type.trim_left('?&')
					is_v_interface := v_pure in m.env.state.known_interfaces
					// If we are matching to return an interface, OMIT NoneType branch from the match itself.
					// None should be handled by the outer 'if mut val_raw := ...' or by 'ret_match_val' default.
					if (v_type == 'Any' || v_type == '') && !is_v_interface && pure == 'Any' {
						m.emit('    NoneType { ret_match_val = none }')
					}
					m.emit("    else { panic('cannot cast Any to interface ${pure}') }")
					m.emit('}')
					m.env.state.indent_level--
					m.emit('}')
					if is_opt_target {
						m.emit('return ret_match_val')
					} else {
						m.emit('return ${pure}(ret_match_val or { panic("missing return value") })')
					}
				} else {
				if expr.contains('(') && !expr.starts_with('(') && !expr.contains(' or {') && (v_type.starts_with('?') || v_type == 'Any') {
					// Add unwrap for potential Option return from method calls when casting to interface
					m.emit('return ${pure}((${expr} or { panic("missing return value") }))')
				} else {
					m.emit('return ${pure}(${expr})')
				}
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

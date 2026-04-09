module control_flow

import analyzer
import ast
import base

pub struct AssignedVar {
pub:
	name   string
	target ast.Expression
	value  ?ast.Expression
}

pub struct ControlFlowVisitEnv {
pub mut:
	state                &base.TranslatorState
	analyzer             &analyzer.Analyzer
	visit_stmt_fn        ?fn (ast.Statement)
	visit_expr_fn        ?fn (ast.Expression) string
	emit_fn              ?fn (string)
	indent_fn            ?fn () string
	declare_local_fn     ?fn (string)
	is_declared_local_fn ?fn (string) bool
	guess_type_fn        ?fn (ast.Expression) string
	map_annotation_fn    ?fn (ast.Expression) string
}

pub struct ControlFlowModule {
pub mut:
	env                ControlFlowVisitEnv
	loop_flag_stack    []string
	loop_depth_stack    []int
	in_finally          bool
}

fn noop_visit_stmt(_ ast.Statement) {}

fn noop_visit_expr(_ ast.Expression) string {
	return ''
}

fn noop_emit(_ string) {}

pub fn new_control_flow_visit_env(
	state &base.TranslatorState,
	analyzer_ref &analyzer.Analyzer,
	visit_stmt_fn fn (ast.Statement),
	visit_expr_fn fn (ast.Expression) string,
	emit_fn fn (string),
	indent_fn fn () string,
	declare_local_fn fn (string),
	is_declared_local_fn fn (string) bool,
	guess_type_fn fn (ast.Expression) string,
	map_annotation_fn fn (ast.Expression) string,
) ControlFlowVisitEnv {
	return ControlFlowVisitEnv{
		state:                state
		analyzer:             analyzer_ref
		visit_stmt_fn:        visit_stmt_fn
		visit_expr_fn:        visit_expr_fn
		emit_fn:              emit_fn
		indent_fn:            indent_fn
		declare_local_fn:     declare_local_fn
		is_declared_local_fn: is_declared_local_fn
		guess_type_fn:        guess_type_fn
		map_annotation_fn:    map_annotation_fn
	}
}

pub fn new_control_flow_module() ControlFlowModule {
	mut s := base.new_translator_state()
	mut a := analyzer.new_analyzer(map[string]string{})
	return ControlFlowModule{
		env: ControlFlowVisitEnv{
			state:                s
			analyzer:             a
			visit_stmt_fn:        noop_visit_stmt
			visit_expr_fn:        noop_visit_expr
			emit_fn:              noop_emit
			indent_fn:            none
			declare_local_fn:     none
			is_declared_local_fn: none
			guess_type_fn:        none
			map_annotation_fn:    none
		}
		loop_flag_stack: []string{}
		loop_depth_stack: []int{}
		in_finally:      false
	}
}

pub fn (m &ControlFlowModule) indent() string {
	if f := m.env.indent_fn {
		return f()
	}
	return m.env.state.indent()
}

pub fn (mut m ControlFlowModule) emit(line string) {
	if f := m.env.emit_fn {
		f(line)
	} else {
		m.env.state.output << '${m.indent()}${line}'
	}
}

pub fn (mut m ControlFlowModule) visit_stmt(node ast.Statement) {
	if f := m.env.visit_stmt_fn {
		f(node)
	}
}

pub fn (mut m ControlFlowModule) visit_expr(node ast.Expression) string {
	if f := m.env.visit_expr_fn {
		return f(node)
	}
	return ''
}

pub fn (mut m ControlFlowModule) guess_type(node ast.Expression) string {
	if f := m.env.guess_type_fn {
		return f(node)
	}
	return 'Any'
}

pub fn (mut m ControlFlowModule) map_annotation(node ast.Expression) string {
	if f := m.env.map_annotation_fn {
		return f(node)
	}
	return ''
}

pub fn (mut m ControlFlowModule) declare_local(name string) {
	if f := m.env.declare_local_fn {
		f(name)
	}
}

pub fn (mut m ControlFlowModule) is_declared_local(name string) bool {
	if f := m.env.is_declared_local_fn {
		return f(name)
	}
	return false
}

pub fn (mut m ControlFlowModule) wrap_bool(node ast.Expression, invert bool) string {
	expr := m.visit_expr(node)
	v_type := m.guess_type(node)
	return base.wrap_bool(node, expr, v_type, invert)
}

pub fn (m &ControlFlowModule) sanitize_name(name string, is_type bool) string {
	return base.sanitize_name(name, is_type, map[string]bool{}, '', map[string]bool{})
}


pub fn (m &ControlFlowModule) map_python_type(type_str string, is_return bool) string {
	opts := base.TypeMapOptions{
		struct_name:        m.env.state.current_class
		allow_union:        true
		register_sum_types: true
		is_return:          is_return
		generic_map:        m.env.state.current_class_generic_map
	}
	mut ctx := base.TypeUtilsContext{
		imported_symbols: m.env.state.imported_symbols
		scc_files:        m.env.state.scc_files.keys()
		used_builtins:    m.env.state.used_builtins
		warnings:         m.env.state.warnings
		include_all_symbols: m.env.state.include_all_symbols
		strict_exports:      m.env.state.strict_exports
	}
	return base.map_type(type_str, opts, mut ctx, fn (_ string, _ string) string { return '' },
		fn (_ []string) string { return '' }, fn (_ string) string { return '' })
}

pub fn (m &ControlFlowModule) register_sum_type(types_str string) string {
	opts := base.TypeMapOptions{
		struct_name:        m.env.state.current_class
		allow_union:        true
		register_sum_types: true
		is_return:          false
		generic_map:        m.env.state.current_class_generic_map
	}
	mut ctx := base.TypeUtilsContext{
		imported_symbols: m.env.state.imported_symbols
		scc_files:        m.env.state.scc_files.keys()
		used_builtins:    m.env.state.used_builtins
		warnings:         m.env.state.warnings
		include_all_symbols: m.env.state.include_all_symbols
		strict_exports:      m.env.state.strict_exports
	}
	mut st := m.env.state
	return base.map_type(types_str, opts, mut ctx, fn [mut st] (name string, def string) string {
		if name.len > 0 {
			st.generated_sum_types[name] = def
			return name
		}
		return ''
	}, fn (_ []string) string { return '' }, fn (_ string) string { return '' })
}

pub fn (m &ControlFlowModule) collect_assigned_vars(nodes []ast.Statement) []AssignedVar {
	mut vars := []AssignedVar{}
	mut seen := map[string]bool{}
	for node in nodes {
		if node is ast.Assign {
			for target in node.targets {
				if target is ast.Name {
					if target.id !in seen {
						vars << AssignedVar{target.id, target, node.value}
						seen[target.id] = true
					}
				} else if target is ast.Attribute {
					if target.value is ast.Name {
						id := target.value.id + '.' + target.attr
						if id !in seen {
							vars << AssignedVar{id, target, node.value}
							seen[id] = true
						}
					}
				}
			}
		} else if node is ast.AnnAssign {
			if node.target is ast.Name {
				if node.target.id !in seen {
					vars << AssignedVar{node.target.id, node.target, node.value}
					seen[node.target.id] = true
				}
			}
		} else if node is ast.For {
			if node.target is ast.Name {
				if node.target.id !in seen {
					vars << AssignedVar{node.target.id, node.target, none}
					seen[node.target.id] = true
				}
			}
		} else if node is ast.With {
			for item in node.items {
				if opt := item.optional_vars {
					if opt is ast.Name {
						if opt.id !in seen {
							vars << AssignedVar{opt.id, opt, none}
							seen[opt.id] = true
						}
					}
				}
			}
		}
	}
	return vars
}

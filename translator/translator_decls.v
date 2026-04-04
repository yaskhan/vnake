module translator

import ast
import classes
import functions

// Class translation logic has been moved to classes/ module.


fn (mut t Translator) visit_function_def(node &ast.FunctionDef) {
	prev_func := t.current_function_name
	t.current_function_name = node.name
	
	old_output := t.state.output
	t.state.output = []string{}
	
	mut env := functions.new_function_visit_env(
		t.state,
		t.analyzer,
		fn [mut t] (stmt ast.Statement) {
			t.visit_stmt(stmt)
		},
		fn [mut t] (expr ast.Expression) string {
			return t.visit_expr(expr)
		},
		fn [mut t] (line string) {
			t.state.output << line
		},
		fn [mut t] (line string) {
			t.emit_constant_code(line)
		},
		fn [mut t] (line string) {
			t.emit_function_code(line)
		},
		fn [mut t] () string {
			return t.indent()
		},
		fn [mut t] () {
			t.push_scope()
		},
		fn [mut t] () {
			t.pop_scope()
		},
		fn [mut t] (name string) {
			t.declare_local(name)
		},
		fn [mut t] (ann ast.Expression) string {
			return t.map_annotation(ann)
		},
		fn [mut t] (type_str string, struct_name string, allow_union bool, register bool, is_return bool) string {
			return t.map_annotation_str(type_str, struct_name, allow_union, register, is_return)
		},
		false,
	)
	t.functions_module.visit_function_def(node, mut env)
	
	func_code := t.state.output.join('\n')
	t.state.output = old_output
	t.current_function_name = prev_func
	
	if func_code.len > 0 {
		if prev_func.len > 0 {
			t.state.output << func_code
		} else {
			t.emit_function_code(func_code)
		}
	}
}

fn (mut t Translator) visit_class_def(node &ast.ClassDef) {
	old_output := t.state.output
	t.state.output = []string{}
	
	mut env := classes.new_class_visit_env(
		t.state,
		t.analyzer,
		fn [mut t] (stmt ast.Statement) {
			t.visit_stmt(stmt)
		},
		fn [mut t] (expr ast.Expression) string {
			return t.visit_expr(expr)
		},
		fn [mut t] (s string) {
			t.state.output << s
		},
		fn [mut t] (s string) {
			t.emit_function_code(s)
		},
		fn [mut t] (s string) {
			t.emit_constant_code(s)
		},
		fn [mut t] (type_str string, struct_name string, allow_union bool, register bool, is_return bool) string {
			return t.map_annotation_str(type_str, struct_name, allow_union, register, is_return)
		},
		fn [mut t] (ann ast.Expression) string {
			return t.map_annotation(ann)
		},
		false,
	)
	t.classes_module.visit_class_def(node, mut env)
	
	class_struct_code := t.state.output.join('\n')
	t.state.output = old_output
	
	if class_struct_code.len > 0 {
		t.emit_struct_code(class_struct_code)
	}
}

fn (mut t Translator) emit_struct_code(s string) {
	mut e := unsafe { &VCodeEmitter(t.state.emitter) }
	e.add_struct(s)
}

fn (mut t Translator) emit_function_code(s string) {
	mut e := unsafe { &VCodeEmitter(t.state.emitter) }
	e.add_function(s)
}

fn (mut t Translator) emit_constant_code(s string) {
	mut e := unsafe { &VCodeEmitter(t.state.emitter) }
	e.add_constant(s)
}

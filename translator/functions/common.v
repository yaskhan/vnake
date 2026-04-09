module functions

import ast

fn scan_type_expr(expr ast.Expression, type_vars map[string]bool, mut found map[string]bool) {
	match expr {
		ast.Name {
			if expr.id in type_vars {
				found[expr.id] = true
			}
		}
		ast.Attribute {
			if expr.attr in type_vars {
				found[expr.attr] = true
			}
			scan_type_expr(expr.value, type_vars, mut found)
		}
		ast.Subscript {
			scan_type_expr(expr.value, type_vars, mut found)
			scan_type_expr(expr.slice, type_vars, mut found)
		}
		ast.Tuple {
			for item in expr.elements {
				scan_type_expr(item, type_vars, mut found)
			}
		}
		ast.List {
			for item in expr.elements {
				scan_type_expr(item, type_vars, mut found)
			}
		}
		ast.Set {
			for item in expr.elements {
				scan_type_expr(item, type_vars, mut found)
			}
		}
		ast.Dict {
			for key in expr.keys {
				scan_type_expr(key, type_vars, mut found)
			}
			for value in expr.values {
				scan_type_expr(value, type_vars, mut found)
			}
		}
		ast.Call {
			scan_type_expr(expr.func, type_vars, mut found)
			for arg in expr.args {
				scan_type_expr(arg, type_vars, mut found)
			}
			for kw in expr.keywords {
				scan_type_expr(kw.value, type_vars, mut found)
			}
		}
		ast.BinaryOp {
			scan_type_expr(expr.left, type_vars, mut found)
			scan_type_expr(expr.right, type_vars, mut found)
		}
		ast.UnaryOp {
			scan_type_expr(expr.operand, type_vars, mut found)
		}
		ast.Compare {
			scan_type_expr(expr.left, type_vars, mut found)
			for comparator in expr.comparators {
				scan_type_expr(comparator, type_vars, mut found)
			}
		}
		ast.IfExp {
			scan_type_expr(expr.test, type_vars, mut found)
			scan_type_expr(expr.body, type_vars, mut found)
			scan_type_expr(expr.orelse, type_vars, mut found)
		}
		ast.JoinedStr {
			for value in expr.values {
				scan_type_expr(value, type_vars, mut found)
			}
		}
		ast.FormattedValue {
			scan_type_expr(expr.value, type_vars, mut found)
			if format_spec := expr.format_spec {
				scan_type_expr(format_spec, type_vars, mut found)
			}
		}
		ast.ListComp {
			scan_type_expr(expr.elt, type_vars, mut found)
			for generator in expr.generators {
				scan_type_expr(generator.target, type_vars, mut found)
				scan_type_expr(generator.iter, type_vars, mut found)
				for cond in generator.ifs {
					scan_type_expr(cond, type_vars, mut found)
				}
			}
		}
		ast.SetComp {
			scan_type_expr(expr.elt, type_vars, mut found)
			for generator in expr.generators {
				scan_type_expr(generator.target, type_vars, mut found)
				scan_type_expr(generator.iter, type_vars, mut found)
				for cond in generator.ifs {
					scan_type_expr(cond, type_vars, mut found)
				}
			}
		}
		ast.DictComp {
			scan_type_expr(expr.key, type_vars, mut found)
			scan_type_expr(expr.value, type_vars, mut found)
			for generator in expr.generators {
				scan_type_expr(generator.target, type_vars, mut found)
				scan_type_expr(generator.iter, type_vars, mut found)
				for cond in generator.ifs {
					scan_type_expr(cond, type_vars, mut found)
				}
			}
		}
		ast.GeneratorExp {
			scan_type_expr(expr.elt, type_vars, mut found)
			for generator in expr.generators {
				scan_type_expr(generator.target, type_vars, mut found)
				scan_type_expr(generator.iter, type_vars, mut found)
				for cond in generator.ifs {
					scan_type_expr(cond, type_vars, mut found)
				}
			}
		}
		else {}
	}
}

// extract_implicit_generics extracts type vars used in annotations.
pub fn extract_implicit_generics(
	node &ast.FunctionDef,
	type_vars map[string]bool,
	paramspec_vars map[string]bool,
	constrained_typevars map[string]bool,
	current_class_generics []string,
	sanitize_fn fn (string, bool) string,
) []string {
	mut implicit_generics := map[string]bool{}

	mut all_type_vars := type_vars.clone()
	for cg in current_class_generics {
		all_type_vars[cg] = true
	}

	for param in node.args.posonlyargs {
		if annotation := param.annotation {
			scan_type_expr(annotation, all_type_vars, mut implicit_generics)
		}
	}
	for param in node.args.args {
		if annotation := param.annotation {
			scan_type_expr(annotation, all_type_vars, mut implicit_generics)
		}
	}
	for param in node.args.kwonlyargs {
		if annotation := param.annotation {
			scan_type_expr(annotation, all_type_vars, mut implicit_generics)
		}
	}
	if vararg := node.args.vararg {
		if annotation := vararg.annotation {
			scan_type_expr(annotation, all_type_vars, mut implicit_generics)
		}
	}
	if kwarg := node.args.kwarg {
		if annotation := kwarg.annotation {
			scan_type_expr(annotation, all_type_vars, mut implicit_generics)
		}
	}
	if returns := node.returns {
		scan_type_expr(returns, all_type_vars, mut implicit_generics)
	}

	mut filtered := map[string]bool{}
	for gen in implicit_generics.keys() {
		if gen !in constrained_typevars && gen !in paramspec_vars {
			filtered[gen] = true
		}
	}

	for gen in current_class_generics {
		filtered.delete(gen)
	}

	mut result := filtered.keys()
	result.sort()
	return result
}

// find_captured_vars returns closure captures. This implementation keeps the
// interface stable and can be expanded later without changing call sites.
pub fn find_captured_vars(
	node ast.ASTNode,
	scope_stack []map[string]bool,
	sanitize_fn fn (string, bool) string,
) []string {
	mut captured := []string{}
	mut local_scope := map[string]bool{}

	if node is ast.Lambda {
		for arg in node.args.posonlyargs {
			local_scope[arg.arg] = true
		}
		for arg in node.args.args {
			local_scope[arg.arg] = true
		}
		for arg in node.args.kwonlyargs {
			local_scope[arg.arg] = true
		}
		if va := node.args.vararg {
			local_scope[va.arg] = true
		}
		if kw := node.args.kwarg {
			local_scope[kw.arg] = true
		}

		scan_captured(node.body, mut local_scope, scope_stack, sanitize_fn, mut captured)
	} else if node is ast.FunctionDef {
		for arg in node.args.posonlyargs {
			local_scope[arg.arg] = true
		}
		for arg in node.args.args {
			local_scope[arg.arg] = true
		}
		for arg in node.args.kwonlyargs {
			local_scope[arg.arg] = true
		}
		if va := node.args.vararg {
			local_scope[va.arg] = true
		}
		if kw := node.args.kwarg {
			local_scope[kw.arg] = true
		}
		
		scan_captured_body(node.body, mut local_scope, scope_stack, sanitize_fn, mut captured)
	}

	return captured
}

fn scan_captured_body(body []ast.Statement, mut local_scope map[string]bool, scope_stack []map[string]bool, sanitize_fn fn (string, bool) string, mut captured []string) {
	for stmt in body {
		scan_captured_stmt(stmt, mut local_scope, scope_stack, sanitize_fn, mut captured)
	}
}

fn scan_captured_stmt(stmt ast.Statement, mut local_scope map[string]bool, scope_stack []map[string]bool, sanitize_fn fn (string, bool) string, mut captured []string) {
	match stmt {
		ast.Assign {
			scan_captured(stmt.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
			for t in stmt.targets { add_to_scope(t, mut local_scope) }
		}
		ast.AnnAssign {
			if val := stmt.value { scan_captured(val, mut local_scope, scope_stack, sanitize_fn, mut captured) }
			add_to_scope(stmt.target, mut local_scope)
		}
		ast.Expr {
			scan_captured(stmt.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.Return {
			if val := stmt.value { scan_captured(val, mut local_scope, scope_stack, sanitize_fn, mut captured) }
		}
		ast.If {
			scan_captured(stmt.test, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured_body(stmt.body, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured_body(stmt.orelse, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.For {
			scan_captured(stmt.iter, mut local_scope, scope_stack, sanitize_fn, mut captured)
			mut nested_local := local_scope.clone()
			add_to_scope(stmt.target, mut nested_local)
			scan_captured_body(stmt.body, mut nested_local, scope_stack, sanitize_fn, mut captured)
			scan_captured_body(stmt.orelse, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.While {
			scan_captured(stmt.test, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured_body(stmt.body, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured_body(stmt.orelse, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.With {
			for item in stmt.items {
				scan_captured(item.context_expr, mut local_scope, scope_stack, sanitize_fn, mut captured)
				if vars := item.optional_vars { add_to_scope(vars, mut local_scope) }
			}
			scan_captured_body(stmt.body, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.Try {
			scan_captured_body(stmt.body, mut local_scope, scope_stack, sanitize_fn, mut captured)
			for h in stmt.handlers {
				mut h_local := local_scope.clone()
				if name := h.name { h_local[name] = true }
				scan_captured_body(h.body, mut h_local, scope_stack, sanitize_fn, mut captured)
			}
			scan_captured_body(stmt.orelse, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured_body(stmt.finalbody, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.FunctionDef {
			local_scope[stmt.name] = true
			// Nested functions can also capture, but they don't capture into the CURRENT function's list directly.
			// However, if the nested function references something from outer, it's already scanned when WE scan that nested function's body if we wanted to.
			// But Python's capture is simpler: just references.
		}
		else {}
	}
}

fn add_to_scope(node ast.Expression, mut scope map[string]bool) {
	match node {
		ast.Name {
			scope[node.id] = true
		}
		ast.Tuple {
			for el in node.elements {
				add_to_scope(el, mut scope)
			}
		}
		ast.List {
			for el in node.elements {
				add_to_scope(el, mut scope)
			}
		}
		else {}
	}
}

fn scan_captured(node ast.Expression, mut local_scope map[string]bool, scope_stack []map[string]bool, sanitize_fn fn (string, bool) string, mut captured []string) {
	match node {
		ast.Name {
			if node.ctx == .load {
				if node.id !in local_scope {
					mut found_in_outer := false
					for i := scope_stack.len - 1; i >= 0; i-- {
						if node.id in scope_stack[i] {
							found_in_outer = true
							break
						}
					}
					if found_in_outer {
						sanitized := sanitize_fn(node.id, false)
						if sanitized !in captured {
							captured << sanitized
						}
					}
				}
			}
		}
		ast.BinaryOp {
			scan_captured(node.left, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured(node.right, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.UnaryOp {
			scan_captured(node.operand, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.Call {
			scan_captured(node.func, mut local_scope, scope_stack, sanitize_fn, mut captured)
			for arg in node.args {
				scan_captured(arg, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
			for kw in node.keywords {
				scan_captured(kw.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.Lambda {
			mut nested_local := local_scope.clone()
			for arg in node.args.posonlyargs {
				nested_local[arg.arg] = true
			}
			for arg in node.args.args {
				nested_local[arg.arg] = true
			}
			for arg in node.args.kwonlyargs {
				nested_local[arg.arg] = true
			}
			if va := node.args.vararg {
				nested_local[va.arg] = true
			}
			if kw := node.args.kwarg {
				nested_local[kw.arg] = true
			}
			scan_captured(node.body, mut nested_local, scope_stack, sanitize_fn, mut captured)
		}
		ast.Attribute {
			scan_captured(node.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.Subscript {
			scan_captured(node.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured(node.slice, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.IfExp {
			scan_captured(node.test, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured(node.body, mut local_scope, scope_stack, sanitize_fn, mut captured)
			scan_captured(node.orelse, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.List {
			for el in node.elements {
				scan_captured(el, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.Tuple {
			for el in node.elements {
				scan_captured(el, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.Set {
			for el in node.elements {
				scan_captured(el, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.Dict {
			for k in node.keys {
				if k !is ast.NoneExpr {
					scan_captured(k, mut local_scope, scope_stack, sanitize_fn, mut captured)
				}
			}
			for v in node.values {
				scan_captured(v, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.JoinedStr {
			for val in node.values {
				scan_captured(val, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.FormattedValue {
			scan_captured(node.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
			if spec := node.format_spec {
				scan_captured(spec, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.ListComp {
			mut comp_local := local_scope.clone()
			for gen in node.generators {
				scan_captured(gen.iter, mut local_scope, scope_stack, sanitize_fn, mut captured)
				add_to_scope(gen.target, mut comp_local)
				for cond in gen.ifs {
					scan_captured(cond, mut comp_local, scope_stack, sanitize_fn, mut captured)
				}
			}
			scan_captured(node.elt, mut comp_local, scope_stack, sanitize_fn, mut captured)
		}
		ast.SetComp {
			mut comp_local := local_scope.clone()
			for gen in node.generators {
				scan_captured(gen.iter, mut local_scope, scope_stack, sanitize_fn, mut captured)
				add_to_scope(gen.target, mut comp_local)
				for cond in gen.ifs {
					scan_captured(cond, mut comp_local, scope_stack, sanitize_fn, mut captured)
				}
			}
			scan_captured(node.elt, mut comp_local, scope_stack, sanitize_fn, mut captured)
		}
		ast.DictComp {
			mut comp_local := local_scope.clone()
			for gen in node.generators {
				scan_captured(gen.iter, mut local_scope, scope_stack, sanitize_fn, mut captured)
				add_to_scope(gen.target, mut comp_local)
				for cond in gen.ifs {
					scan_captured(cond, mut comp_local, scope_stack, sanitize_fn, mut captured)
				}
			}
			scan_captured(node.key, mut comp_local, scope_stack, sanitize_fn, mut captured)
			scan_captured(node.value, mut comp_local, scope_stack, sanitize_fn, mut captured)
		}
		ast.GeneratorExp {
			mut comp_local := local_scope.clone()
			for gen in node.generators {
				scan_captured(gen.iter, mut local_scope, scope_stack, sanitize_fn, mut captured)
				add_to_scope(gen.target, mut comp_local)
				for cond in gen.ifs {
					scan_captured(cond, mut comp_local, scope_stack, sanitize_fn, mut captured)
				}
			}
			scan_captured(node.elt, mut comp_local, scope_stack, sanitize_fn, mut captured)
		}
		ast.Compare {
			scan_captured(node.left, mut local_scope, scope_stack, sanitize_fn, mut captured)
			for comparator in node.comparators {
				scan_captured(comparator, mut local_scope, scope_stack, sanitize_fn, mut captured)
			}
		}
		ast.Starred {
			scan_captured(node.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
		}
		ast.NamedExpr {
			scan_captured(node.value, mut local_scope, scope_stack, sanitize_fn, mut captured)
			add_to_scope(node.target, mut local_scope)
		}
		else {}
	}
}

// is_empty_body checks whether a function body is effectively empty.
pub fn is_empty_body(body []ast.Statement) bool {
	for stmt in body {
		if stmt is ast.Pass {
			continue
		}
		if stmt is ast.Expr {
			expr_stmt := stmt
			if expr_stmt.value is ast.Constant {
				if expr_stmt.value.value == '...' || expr_stmt.value.value.starts_with("'''")
					|| expr_stmt.value.value.starts_with('"""') {
					continue
				}
			}
		}
		if stmt is ast.Raise {
			raise_stmt := stmt
			if exc := raise_stmt.exc {
				if exc is ast.Name {
					if exc.id == 'NotImplementedError' {
						continue
					}
				} else if exc is ast.Call {
					if exc.func is ast.Name && exc.func.id == 'NotImplementedError' {
						continue
					}
				} else {
					continue
				}
			}
		}
		return false
	}
	return true
}

// ends_with_return checks whether a block of statements ends with a return.
pub fn ends_with_return(body []ast.Statement) bool {
	if body.len == 0 {
		return false
	}
	last_stmt := body.last()
	return stmt_ends_with_return(last_stmt)
}

fn stmt_ends_with_return(stmt ast.Statement) bool {
	match stmt {
		ast.Return {
			return true
		}
		ast.Raise {
			return true
		}
		ast.If {
			if stmt.orelse.len == 0 {
				return false
			}
			return ends_with_return(stmt.body) && ends_with_return(stmt.orelse)
		}
		ast.Try {
			// If finalbody exists and ends with return, it's enough.
			if stmt.finalbody.len > 0 && ends_with_return(stmt.finalbody) {
				return true
			}
			// If all paths (body, all handlers, orelse) end with return, it's enough.
			if !ends_with_return(stmt.body) {
				return false
			}
			for handler in stmt.handlers {
				if !ends_with_return(handler.body) {
					return false
				}
			}
			// if orelse exists, it must also end with return (orelse is executed if no exception)
			if stmt.orelse.len > 0 && !ends_with_return(stmt.orelse) {
				return false
			}
			return true
		}
		ast.Match {
			if stmt.cases.len == 0 { return false }
			// Find if there's a wildcard case (match anything)
			mut has_wildcard := false
			for case in stmt.cases {
				if case.pattern is ast.MatchAs {
					if case.pattern.name == none {
						has_wildcard = true
					}
				}
				if !ends_with_return(case.body) {
					return false
				}
			}
			return has_wildcard
		}
		else {
			return false
		}
	}
}

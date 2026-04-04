module base

import ast
import models
import analyzer

pub type TypeGuessingContext = models.TypeGuessingContext

// guess_type infers a best-effort V type for an expression node.
pub fn guess_type(node ast.Expression, ctx TypeGuessingContext, use_location bool) string {
	if use_location {
		loc_key := '${node.get_token().line}:${node.get_token().column}'
		if loc_key in ctx.location_map {
			res := ctx.location_map[loc_key]
			if res != 'none' && res != 'Any' && res != 'unknown' {
				return res
			}
		}
	}

	match node {
		ast.Constant { return guess_constant_type(node) }
		ast.Name { return guess_type_name(node, ctx, use_location) }
		ast.Attribute { return guess_type_attribute(node, ctx, use_location) }
		ast.Subscript { return guess_type_subscript(node, ctx, use_location) }
		ast.Call { return guess_type_call(node, ctx, use_location) }
		ast.Lambda { return guess_type_lambda(node, ctx) }
		ast.UnaryOp {
			if node.op.value == 'not' { return 'bool' }
			return guess_type(node.operand, ctx, use_location)
		}
		ast.BinaryOp { return guess_type_binop(node, ctx) }
		ast.Compare { return 'bool' }
		ast.BoolOp { return 'bool' }
		ast.List { return guess_type_list(node, ctx) }
		ast.Tuple { return guess_type_list(node, ctx) }
		ast.Set { return guess_type_set(node, ctx) }
		ast.Dict { return guess_type_dict(node, ctx) }
		ast.ListComp { return guess_type_listcomp(node, ctx) }
		ast.GeneratorExp { return guess_type_listcomp(node, ctx) }
		ast.DictComp { return guess_type_dictcomp(node, ctx) }
		ast.SetComp { return guess_type_setcomp(node, ctx) }
		else { return 'Any' }
	}
}

fn guess_constant_type(node ast.Constant) string {
	tok := node.token
	if tok.typ == .string_tok || tok.typ == .fstring_tok || tok.typ == .tstring_tok {
		return 'string'
	}
	if tok.typ == .number {
		if node.value.contains('.') || node.value.contains('e') || node.value.contains('E') {
			return 'f64'
		}
		return 'int'
	}
	if tok.typ == .keyword {
		if node.value in ['True', 'False'] { return 'bool' }
		if node.value == 'None' { return 'none' }
	}
	return 'Any'
}

fn guess_type_name(node ast.Name, ctx TypeGuessingContext, use_location bool) string {
	if use_location {
		loc_key := '${node.token.line}:${node.token.column}'
		if loc_key in ctx.location_map {
			return ctx.location_map[loc_key]
		}
	}
	actual_name := ctx.name_remap[node.id] or { node.id }
	if actual_name.starts_with('(') && actual_name.contains(' as ') {
		return actual_name.all_after(' as ').all_before(')').trim_space()
	}
	if actual_name in ctx.explicit_any_types || node.id in ctx.explicit_any_types {
		return 'Any'
	}
	if use_location {
		loc_key_alt := '${node.id}@${node.token.line}:${node.token.column}'
		if loc_key_alt in ctx.explicit_any_types { return 'Any' }
		if loc_key_alt in ctx.type_map { return ctx.type_map[loc_key_alt] }
	}
	if actual_name in ctx.known_v_types { return ctx.known_v_types[actual_name] }
	if node.id in ctx.known_v_types { return ctx.known_v_types[node.id] }

	if node.id in ctx.type_map {
		res := ctx.type_map[node.id]
		if res != 'int' && res != 'Any' && res != 'unknown' { return res }
	}
	if ctx.analyzer != unsafe { nil } {
		analyzer_ptr := unsafe { &analyzer.Analyzer(ctx.analyzer) }
		loc_key := '${node.token.line}:${node.token.column}'
		if res := analyzer_ptr.get_mypy_type(node.id, loc_key) {
			return analyzer.map_python_type_to_v(res)
		}
		if res := analyzer_ptr.get_mypy_type('', loc_key) {
			return analyzer.map_python_type_to_v(res)
		}
		if res := analyzer_ptr.get_mypy_type(node.str(), loc_key) {
			return analyzer.map_python_type_to_v(res)
		}
		if res := analyzer_ptr.mypy_store.collected_types[node.id] {
			mut closest_typ := ''
			mut min_dist := 1000000
			line_num := node.token.line
			for k, v in res {
				l := k.all_before(':').int()
				if l > 0 {
					dist := if l <= line_num { line_num - l } else { l - line_num }
					if dist < min_dist {
						min_dist = dist
						closest_typ = v
					}
				}
			}
			if closest_typ != '' { return analyzer.map_python_type_to_v(closest_typ) }
		}
		if analyzer_ptr.has_type(node.id) {
			return analyzer_ptr.get_type(node.id) or { 'int' }
		}
	}
	return 'int'
}

fn guess_type_attribute(node ast.Attribute, ctx TypeGuessingContext, use_location bool) string {
	if use_location {
		loc_key := '${node.token.line}:${node.token.column}'
		if loc_key in ctx.location_map {
			return ctx.location_map[loc_key]
		}
		if ctx.analyzer != unsafe { nil } {
			a := unsafe { &analyzer.Analyzer(ctx.analyzer) }
			full_name := analyzer.expr_name(node)
			if res := a.get_mypy_type(full_name, loc_key) {
				return analyzer.map_python_type_to_v(res)
			}
			if res := a.get_mypy_type(node.attr, loc_key) {
				return analyzer.map_python_type_to_v(res)
			}
		}
	}

	val_type := guess_type(node.value, ctx, false)
	base_type := val_type.trim_left('?&')
	if base_type != 'Any' && base_type != 'int' {
		attr_name := '${base_type}.${node.attr}'
		if attr_name in ctx.type_map { return ctx.type_map[attr_name] }
		if ctx.analyzer != unsafe { nil } {
			a := unsafe { &analyzer.Analyzer(ctx.analyzer) }
			if a.has_type(attr_name) {
				return a.get_type(attr_name) or { 'Any' }
			}
		}
	}

	if node.value is ast.Name {
		attr_name := '${node.value.id}.${node.attr}'
		if attr_name in ctx.type_map { return ctx.type_map[attr_name] }
	}
	return 'Any'
}

fn guess_type_subscript(node ast.Subscript, ctx TypeGuessingContext, use_location bool) string {
	if use_location {
		loc_key := '${node.token.line}:${node.token.column}'
		if loc_key in ctx.location_map {
			return ctx.location_map[loc_key]
		}
	}
	val_type := guess_type(node.value, ctx, true)
	if val_type.starts_with("[]") { return val_type[2..] }
	if val_type.starts_with("map[") && val_type.contains("]") { return val_type.all_after("]") }
	return 'Any'
}

fn guess_type_call(node ast.Call, ctx TypeGuessingContext, use_location bool) string {
	if use_location {
		loc_key := '${node.token.line}:${node.token.column}'
		if loc_key in ctx.location_map { return ctx.location_map[loc_key] }
	}
	if node.func is ast.Name {
		fid := node.func.id
		if fid in ctx.defined_classes { return fid }
		if fid.starts_with('new_') {
			return base.sanitize_name(fid[4..], true, map[string]bool{}, '', map[string]bool{})
		}
		if fid == 'str' { return 'string' }
		if fid in ['int', 'len'] { return 'int' }
		if fid == 'float' { return 'f64' }
		if fid in ['bool', 'isinstance', 'hasattr'] { return 'bool' }
	}
	return 'Any'
}

fn guess_type_list(node ast.Expression, ctx TypeGuessingContext) string {
	mut elements := []ast.Expression{}
	if node is ast.List { elements = node.elements.clone() }
	else if node is ast.Tuple { elements = node.elements.clone() }

	if elements.len == 0 { return '[]Any' }
	t := guess_type(elements[0], ctx, true)
	return '[]${t}'
}

fn guess_type_set(node ast.Set, ctx TypeGuessingContext) string {
	if node.elements.len == 0 { return 'datatypes.Set[Any]' }
	t := guess_type(node.elements[0], ctx, true)
	return 'datatypes.Set[${t}]'
}

fn guess_type_dict(node ast.Dict, ctx TypeGuessingContext) string {
	if node.keys.len == 0 { return 'map[string]Any' }
	kt := guess_type(node.keys[0], ctx, true)
	vt := guess_type(node.values[0], ctx, true)
	return 'map[${kt}]${vt}'
}

fn guess_type_binop(node ast.BinaryOp, ctx TypeGuessingContext) string {
	left := guess_type(node.left, ctx, true)
	right := guess_type(node.right, ctx, true)
	if node.op.value == '/' { return 'f64' }
	if left == 'f64' || right == 'f64' { return 'f64' }
	if left == 'int' && right == 'int' { return 'int' }
	return 'Any'
}

fn guess_type_listcomp(node ast.Expression, ctx TypeGuessingContext) string {
	mut elt := ast.Expression(ast.NoneExpr{})
	if node is ast.ListComp { elt = node.elt }
	else if node is ast.GeneratorExp { elt = node.elt }
	return '[]' + guess_type(elt, ctx, true)
}

fn guess_type_dictcomp(node ast.DictComp, ctx TypeGuessingContext) string {
	kt := guess_type(node.key, ctx, true)
	vt := guess_type(node.value, ctx, true)
	return 'map[${kt}]${vt}'
}

fn guess_type_setcomp(node ast.SetComp, ctx TypeGuessingContext) string {
	return 'datatypes.Set[' + guess_type(node.elt, ctx, true) + ']'
}

fn guess_type_lambda(node ast.Lambda, ctx TypeGuessingContext) string {
	return 'fn() Any'
}

pub fn is_literal_string_expr(node ast.Expression, ctx TypeGuessingContext) bool {
	if node is ast.Constant {
		return node.token.typ == .string_tok || node.token.typ == .fstring_tok
	}
	return false
}

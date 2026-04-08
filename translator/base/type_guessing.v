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
		if ctx.analyzer != unsafe { nil } {
			a := unsafe { &analyzer.Analyzer(ctx.analyzer) }
			if mypy_type := a.get_mypy_type(node.str(), loc_key) {
				return analyzer.map_python_type_to_v(mypy_type)
			}
		}
	}

	if node is ast.Constant {
		return guess_constant_type(node)
	}
	if node is ast.Lambda {
		return guess_type_lambda(node, ctx)
	}
	if node is ast.UnaryOp {
		if node.op.value == 'not' {
			return 'bool'
		}
		return guess_type(node.operand, ctx, use_location)
	}
	if node is ast.Compare || node is ast.BoolOp {
		return 'bool'
	}
	if node is ast.Call {
		return guess_type_call(node, ctx, use_location)
	}
	if node is ast.List || node is ast.Tuple {
		return guess_type_list(node, ctx)
	}
	if node is ast.Set {
		return guess_type_set(node, ctx)
	}
	if node is ast.Dict {
		return guess_type_dict(node, ctx)
	}
	if node is ast.Name {
		return guess_type_name(node, ctx, use_location)
	}
	if node is ast.Attribute {
		return guess_type_attribute(node, ctx, use_location)
	}
	if node is ast.Subscript {
		return guess_type_subscript(node, ctx, use_location)
	}
	if node is ast.BinaryOp {
		return guess_type_binop(node, ctx)
	}
	if node is ast.ListComp || node is ast.GeneratorExp {
		return guess_type_listcomp(node, ctx)
	}
	if node is ast.SetComp {
		return guess_type_setcomp(node, ctx)
	}
	if node is ast.DictComp {
		return guess_type_dictcomp(node, ctx)
	}
	if node is ast.IfExp {
		bt := guess_type(node.body, ctx, use_location)
		ot := guess_type(node.orelse, ctx, use_location)
		res := if bt == ot { 
			bt 
		} else if bt.starts_with('?') && bt.trim_left('?') == ot { 
			bt 
		} else if ot.starts_with('?') && ot.trim_left('?') == bt { 
			ot 
		} else { 
			'Any' 
		}
		return res
	}
	return 'Any'
}

fn guess_constant_type(node ast.Constant) string {
	tok := node.token
	if tok.typ == .string_tok || tok.typ == .fstring_tok || tok.typ == .tstring_tok {
		if node.value.starts_with("b'") || node.value.starts_with('b"') {
			return '[]u8'
		}
		return 'string'
	}
	if tok.typ == .number {
		if node.value.ends_with('j') {
			return 'PyComplex'
		}
		if node.value.contains('.') || node.value.contains('e') || node.value.contains('E') {
			return 'f64'
		}
		return 'int'
	}
	if tok.typ == .keyword {
		if node.value in ['True', 'False'] {
			return 'bool'
		}
		if node.value == 'None' {
			return 'none'
		}
	}
	return 'Any'
}

fn guess_type_call(node ast.Call, ctx TypeGuessingContext, use_location bool) string {
	if use_location {
		loc_key := '${node.get_token().line}:${node.get_token().column}'
		if loc_key in ctx.location_map {
			res := ctx.location_map[loc_key]
			if res != 'none' && res != 'Any' && res != 'unknown' {
				return res
			}
		}
	}
	if node.func is ast.Name {
		fid := node.func.id
		if fid in ctx.defined_classes {
			return fid
		}
		if ctx.coroutine_handler != unsafe { nil } {
			ch := unsafe { &analyzer.CoroutineHandler(ctx.coroutine_handler) }
			if ch.is_generator(fid) {
				yield_type := ch.generators[fid] or { 'int' }
				return 'PyGenerator[${yield_type}]'
			}
		}
		if fid.len > 0 && fid[0].is_capital() {
			current := ctx.type_map[fid] or { 'Any' }
			if current == '[]Any' { return '[]Any' }
			if current == 'map[string]Any' { return 'map[string]Any' }
		}
		if fid.starts_with('new_') {
			return base.sanitize_name(fid[4..], true, map[string]bool{}, '', map[string]bool{})
		}
		if fid == 'str' {
			if node.args.len > 0 && is_literal_string_expr(node.args[0], ctx) {
				return 'LiteralString'
			}
			return 'string'
		}
		if fid in ['int', 'len'] {
			return 'int'
		}
		if fid == 'float' {
			return 'f64'
		}
		if fid in ['bool', 'isinstance', 'hasattr', 'getattr', 'setattr'] {
			return 'bool'
		}
		if fid == 'print' {
			return 'None'
		}
		if fid == 'input' {
			return 'string'
		}
		if fid == 'open' {
			return 'os.File'
		}
		if fid in ['bytearray', 'memoryview', 'bytes'] {
			return '[]u8'
		}
		if fid in ['set', 'frozenset'] {
			if node.args.len > 0 {
				arg_type := guess_type(node.args[0], ctx, true)
				if arg_type.starts_with('[]') {
					return 'datatypes.Set[${arg_type[2..]}]'
				}
			}
			return 'datatypes.Set[string]'
		}
		if fid == 'Counter' {
			return 'map[string]int'
		}
		if fid == 'defaultdict' && node.args.len > 0 {
			mut d_type := 'Any'
			if node.args[0] is ast.Name {
				id := (node.args[0] as ast.Name).id
				if id == 'int' { d_type = 'int' }
				else if id == 'list' { d_type = '[]int' }
				else if id == 'dict' { d_type = 'map[string]Any' }
			}
			return 'map[string]' + d_type
		}
		if fid in ['sum', 'py_sum'] {
			return 'Any'
		}
		if fid in ['any', 'all', 'py_any', 'py_all'] {
			return 'bool'
		}
		if fid == 'py_range' {
			return '[]int'
		}
		if fid in ['py_sorted', 'py_reversed'] {
			if node.args.len > 0 {
				return guess_type(node.args[0], ctx, true)
			}
			return '[]Any'
		}
		if fid == 'py_zip' {
			return '[]PyZipItem'
		}
		if fid == 'py_enumerate' {
			return '[]PyEnumerateItem'
		}
		if fid == 'py_divmod' {
			if node.args.len > 0 {
				return '[]${guess_type(node.args[0], ctx, true)}'
			}
			return '[]Any'
		}
		if fid in ['py_os_path_split', 'py_os_path_splitext'] {
			return '[]string'
		}

		if fid == 'py_complex' {
			return 'PyComplex'
		}
		if fid == 'py_path_new' {
			return 'PyPath'
		}
		if fid == 'cast' && node.args.len >= 2 {
			return guess_type(node.args[0], ctx, true)
		}
		ret_key := '${fid}@return'
		if ret_key in ctx.type_map {
			return ctx.type_map[ret_key]
		}
	}
	if node.func is ast.Attribute {
		if node.func.attr == 'join' || node.func.attr == 'split' || node.func.attr == 'upper' || node.func.attr == 'lower' || node.func.attr == 'strip' {
			return 'string'
		}
		if node.func.attr in ['append', 'extend', 'add', 'update', 'remove', 'pop', 'clear'] {
			return 'none'
		}
	}
	return 'Any'
}

fn guess_type_list(node ast.Expression, ctx TypeGuessingContext) string {
	if node is ast.List {
		return guess_type_elements(node.elements, ctx)
	} else if node is ast.Tuple {
		return guess_type_elements(node.elements, ctx)
	}
	return '[]Any'
}

// guess_type_elements infers the type of a list or tuple.
// Optimization: Tracks type homogeneity in a single pass to avoid temporary array allocations.
fn guess_type_elements(elements []ast.Expression, ctx TypeGuessingContext) string {
	if elements.len == 0 {
		return '[]Any'
	}

	mut first_type := ''
	mut all_same := true
	mut has_none := false
	mut has_elements := false

	for elt in elements {
		mut current_type := ''
		if elt is ast.Starred {
			current_type = 'Any'
		} else if (elt is ast.Constant && elt.value == 'None') || (elt is ast.Name && elt.id in ['None', 'none']) {
			has_none = true
			continue
		} else {
			current_type = guess_type(elt, ctx, true)
		}

		has_elements = true
		if first_type == '' {
			first_type = current_type
		} else if all_same && current_type != first_type {
			all_same = false
		}
	}

	mut lcs := if has_elements && all_same { first_type } else { 'Any' }
	if has_none {
		return '[]?${lcs}'
	}
	return '[]${lcs}'
}

fn guess_type_set(node ast.Set, ctx TypeGuessingContext) string {
	if node.elements.len == 0 {
		return 'datatypes.Set[string]'
	}
	mut element_types := map[string]bool{}
	for elt in node.elements {
		if elt is ast.Starred {
			element_types['Any'] = true
		} else {
			element_types[guess_type(elt, ctx, true)] = true
		}
	}
	if element_types.len == 1 {
		mut t := ''
		for k, _ in element_types { t = k; break }
		if t == 'Any' {
			return 'datatypes.Set[string]'
		}
		return 'datatypes.Set[${t}]'
	}
	return 'datatypes.Set[string]'
}

// guess_type_dict infers the type of a dictionary literal.
// Optimization: Avoids map allocations by tracking key/value type homogeneity in one pass.
fn guess_type_dict(node ast.Dict, ctx TypeGuessingContext) string {
	if ctx.target_type.len > 0 && ctx.target_type in ctx.defined_classes {
		return ctx.target_type
	}
	if node.keys.len == 0 {
		return 'map[string]Any'
	}

	mut first_k_type := ''
	mut first_v_type := ''
	mut all_k_same := true
	mut all_v_same := true

	for i, k in node.keys {
		v := node.values[i]
		mut current_k := ''
		mut current_v := ''

		if k is ast.NoneExpr {
			current_k = 'string'
			current_v = 'Any'
		} else {
			current_k = guess_type(k, ctx, true)
			current_v = guess_type(v, ctx, true)
		}

		if first_k_type == '' {
			first_k_type = current_k
			first_v_type = current_v
		} else {
			if all_k_same && current_k != first_k_type {
				all_k_same = false
			}
			if all_v_same && current_v != first_v_type {
				all_v_same = false
			}
		}
	}

	mut k_type := if all_k_same { first_k_type } else { 'string' }
	if k_type == 'Any' {
		k_type = 'string'
	}
	mut v_type := if all_v_same { first_v_type } else { 'Any' }

	return 'map[${k_type}]${v_type}'
}

fn guess_type_name(node ast.Name, ctx TypeGuessingContext, use_location bool) string {
	if use_location {
		loc_key := '${node.get_token().line}:${node.get_token().column}'
		if loc_key in ctx.location_map {
			res := ctx.location_map[loc_key]
			if res != 'int' && res != 'Any' && res != 'unknown' { return res }
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
	if val_type.starts_with("[]") {
		return val_type[2..]
	}
	if val_type.starts_with("map[") && val_type.contains("]") {
		return val_type.all_after("]")
	}
	if node.value is ast.Attribute {
		if node.value.value is ast.Name && node.value.value.id == 'sys' && node.value.attr == 'argv' {
			return 'string'
		}
	} else if node.value is ast.Name {
		if node.value.id == 'argv' {
			return 'string'
		}
	}
	return 'Any'
}

fn guess_type_binop(node ast.BinaryOp, ctx TypeGuessingContext) string {
	left := guess_type(node.left, ctx, true)
	right := guess_type(node.right, ctx, true)
	if node.op.value == '/' {
		if left == 'PyComplex' || right == 'PyComplex' {
			return 'PyComplex'
		}
		return 'f64'
	}
	if left.starts_with('[]') {
		return left
	}
	if right.starts_with('[]') {
		return right
	}
	if left == 'LiteralString' && right == 'LiteralString' {
		return 'LiteralString'
	}
	if is_string_type(left) || is_string_type(right) {
		return 'string'
	}
	if left == 'PyComplex' || right == 'PyComplex' {
		return 'PyComplex'
	}
	if left == 'f64' || right == 'f64' {
		return 'f64'
	}
	if left == 'int' && right == 'int' {
		return 'int'
	}
	return 'Any'
}

fn guess_type_listcomp(node ast.Expression, ctx TypeGuessingContext) string {
	mut elt_type := 'Any'
	if node is ast.ListComp {
		elt_type = guess_type(node.elt, ctx, true)
	} else if node is ast.GeneratorExp {
		elt_type = guess_type(node.elt, ctx, true)
	}
	if elt_type in ['Any', 'unknown'] {
		return '[]Any'
	}
	return '[]${elt_type}'
}

fn guess_type_setcomp(node ast.SetComp, ctx TypeGuessingContext) string {
	elt_type := guess_type(node.elt, ctx, true)
	if elt_type in ['Any', 'unknown'] {
		return 'datatypes.Set[string]'
	}
	return 'datatypes.Set[${elt_type}]'
}

fn guess_type_dictcomp(node ast.DictComp, ctx TypeGuessingContext) string {
	mut key_type := guess_type(node.key, ctx, true)
	mut val_type := guess_type(node.value, ctx, true)
	if key_type in ['Any', 'unknown'] {
		key_type = 'string'
	}
	if val_type == 'unknown' {
		val_type = 'Any'
	}
	return 'map[${key_type}]${val_type}'
}

fn guess_type_lambda(node ast.Lambda, ctx TypeGuessingContext) string {
	mut param_types := []string{}
	mut local_ctx := ctx
	local_ctx.type_map = ctx.type_map.clone()
	for arg in node.args.posonlyargs {
		typ := ctx.type_map[arg.arg] or { "int" }
		param_types << typ
		local_ctx.type_map[arg.arg] = typ
	}
	for arg in node.args.args {
		typ := ctx.type_map[arg.arg] or { "int" }
		param_types << typ
		local_ctx.type_map[arg.arg] = typ
	}
	for arg in node.args.kwonlyargs {
		typ := ctx.type_map[arg.arg] or { "int" }
		param_types << typ
		local_ctx.type_map[arg.arg] = typ
	}
	mut ret_type := guess_type(node.body, local_ctx, true)
	if ret_type in ["void", "Any", "unknown"] {
		ret_type = "Any"
	}
	return "fn(${param_types.join(', ')}) ${ret_type}"
}

pub fn is_literal_string_expr(node ast.Expression, ctx TypeGuessingContext) bool {
	if node is ast.Constant {
		return node.token.typ == .string_tok || node.token.typ == .fstring_tok
			|| node.token.typ == .tstring_tok
	}
	if node is ast.JoinedStr {
		for v in node.values {
			if !is_literal_string_expr(v, ctx) {
				return false
			}
		}
		return true
	}
	if node is ast.FormattedValue {
		return is_literal_string_expr(node.value, ctx)
	}
	if node is ast.BinaryOp && node.op.value == '+' {
		return is_literal_string_expr(node.left, ctx) && is_literal_string_expr(node.right, ctx)
	}
	if node is ast.Name {
		return (ctx.type_map[node.id] or { '' }) == 'LiteralString'
	}
	return false
}

module expressions

import ast
import strings
import base

// Local wrappers for base module functions
fn is_collection_type(v_type string) bool {
	return base.is_collection_type(v_type)
}

fn is_numeric_type(v_type string) bool {
	return base.is_numeric_type(v_type)
}

fn is_none_expr(node ast.Expression) bool {
	return (node is ast.Constant && node.value == 'None')
		|| (node is ast.Name && node.id in ['None', 'none'])
		|| node is ast.NoneExpr
}

fn (eg &ExprGen) is_explicit_any(node ast.Expression, typ string) bool {
	if typ != 'Any' { return false }
	token := node.get_token()
	loc_key := '${token.line}:${token.column}'
	if loc_key in eg.analyzer.explicit_any_types { return true }
	if node is ast.Name {
		if node.id in eg.analyzer.explicit_any_types { return true }
		name_loc_key := '${node.id}@${token.line}:${token.column}'
		if name_loc_key in eg.analyzer.explicit_any_types { return true }
	}
	return false
}

fn (eg &ExprGen) should_use_is_none_type(typ string, node ast.Expression) bool {
	if typ.starts_with('?') { return false }
	if typ.starts_with('SumType_') { return true }
	if typ.starts_with('map[') && typ.ends_with(']Any') { return true }
	// For Any type (sum type containing NoneType), always use `is NoneType` check
	// because Any is a sum type and `== none` doesn't work with sum types
	if typ == 'Any' {
		return true
	}
	return false
}




fn (mut eg ExprGen) map_python_percent_to_v_interpolation(fmt_str string, right ast.Expression) ?string {
	mut args := []ast.Expression{}
	if right is ast.Tuple {
		args = right.elements.clone()
	} else {
		args << right
	}

	mut res := strings.new_builder(fmt_str.len * 2)
	res.write_byte(`"`)
	mut i := 0
	mut arg_idx := 0
	for i < fmt_str.len {
		if fmt_str[i] == `%` {
			if i + 1 < fmt_str.len && fmt_str[i+1] == `%` {
				res.write_u8(`%`)
				i += 2
				continue
			}

			// Parse format specifier
			mut j := i + 1
			// Skip flags (only 0 is commonly supported in V interpolation)
			mut flag_zero := false
			for j < fmt_str.len && (fmt_str[j] == `0` || fmt_str[j] == `-` || fmt_str[j] == `+` || fmt_str[j] == ` `) {
				if fmt_str[j] == `0` { flag_zero = true }
				j++
			}

			// Width
			mut width_start := j
			for j < fmt_str.len && fmt_str[j].is_digit() { j++ }
			width_str := fmt_str[width_start..j]

			// Precision
			mut precision_str := ""
			if j < fmt_str.len && fmt_str[j] == `.` {
				j++
				mut prec_start := j
				for j < fmt_str.len && fmt_str[j].is_digit() { j++ }
				precision_str = "." + fmt_str[prec_start..j]
			}

			if j < fmt_str.len {
				spec := fmt_str[j]
				if arg_idx < args.len {
					arg_expr := args[arg_idx]
					arg_idx++
					arg_v := eg.visit(arg_expr)

					res.write_byte(`$`)
					res.write_byte(`{`)
					if spec == `r` {
						eg.state.used_builtins['py_repr'] = true
						res.write_string("py_repr(${arg_v})")
					} else {
						res.write_string(arg_v)
						if width_str.len > 0 || precision_str.len > 0 || spec in [`f`, `x`, `X`] {
							res.write_byte(`:`)
							if flag_zero && width_str.len > 0 {
								res.write_byte(`0`)
							}
							res.write_string(width_str)
							res.write_string(precision_str)
							if spec in [`f`, `x`, `X`] {
								res.write_byte(spec)
							}
						}
					}
					res.write_byte(`}`)
					i = j + 1
					continue
				} else {
					return none
				}
			}
		}
		if fmt_str[i] == `$` {
			res.write_string("\\$")
		} else if fmt_str[i] == `"` {
			res.write_string("\\\"")
		} else {
			res.write_u8(fmt_str[i])
		}
		i++
	}
	res.write_byte(`"`)

	if arg_idx != args.len {
		return none
	}

	return res.str()
}

fn (mut eg ExprGen) format_percent_call(left string, right ast.Expression) string {
	if right is ast.Tuple {
		mut args := []string{}
		for elt in right.elements { args << eg.visit(elt) }
		return "py_string_format(${left}, ${args.join(', ')})"
	}
	return "py_string_format(${left}, ${eg.visit(right)})"
}

fn (mut eg ExprGen) format_percent_bytes(left string, right ast.Expression) string {
	if right is ast.Tuple {
		mut args := []string{}
		for elt in right.elements { args << eg.visit(elt) }
		return "py_bytes_format(${left}, ${args.join(', ')})"
	}
	return "py_bytes_format(${left}, ${eg.visit(right)})"
}

fn (eg &ExprGen) is_set_type(v_type string) bool {
	return (v_type.starts_with('map[') && v_type.ends_with(']bool'))
		|| v_type.starts_with('datatypes.Set[')
}

pub fn (mut eg ExprGen) visit_bin_op(node ast.BinaryOp) string {
	left_type := eg.guess_type(node.left)
	right_type := eg.guess_type(node.right)
	op := node.op.value

	mut op_type := 'void'
	token := node.get_token()
	loc_key := '${token.line}:${token.column}'
	if loc_key in eg.analyzer.location_map {
		op_type = eg.analyzer.location_map[loc_key]
	}

	// Support for string and array repetition
	if op == '*' {
		if left_type == 'string' || left_type == 'LiteralString' {
			return '(${eg.visit(node.left)}).repeat(${eg.visit(node.right)})'
		}
		if right_type == 'string' || right_type == 'LiteralString' {
			return '(${eg.visit(node.right)}).repeat(${eg.visit(node.left)})'
		}
		// List repetition: [val] * n
		if node.left is ast.List && node.left.elements.len == 1 {
			return eg.format_repeated_list_literal(node.left, node.right)
		}
		if node.right is ast.List && node.right.elements.len == 1 {
			return eg.format_repeated_list_literal(node.right, node.left)
		}
		// General array repetition: [1, 2] * n
		if left_type.starts_with('[]') && right_type == 'int' {
			eg.state.used_builtins['py_repeat_list'] = true
			return "py_repeat_list(${eg.visit(node.left)}, ${eg.visit(node.right)})"
		}
		if right_type.starts_with('[]') && left_type == 'int' {
			eg.state.used_builtins['py_repeat_list'] = true
			return "py_repeat_list(${eg.visit(node.right)}, ${eg.visit(node.left)})"
		}
	}
	
	if op == '/' && (left_type == 'PyPath' || left_type == 'pathlib.Path') {
		return '${eg.visit(node.left)}.joinpath(${eg.visit(node.right)})'
	}

	mut left := eg.visit(node.left)
	mut right := eg.visit(node.right)

	// Type-Directed Operator Overloading
	if op_type in ['int', 'f64', 'i64'] {
		l_base := eg.guess_type_no_loc(node.left)
		r_base := eg.guess_type_no_loc(node.right)
		if l_base == 'Any' || l_base.starts_with('SumType_') {
			if !left.contains(' as ') { left = "(${left} as ${op_type})" }
		} else if left_type != op_type && left_type != 'unknown' {
			left = "${op_type}(${left})"
		}
		if r_base == 'Any' || r_base.starts_with('SumType_') {
			if !right.contains(' as ') { right = "(${right} as ${op_type})" }
		} else if right_type != op_type && right_type != 'unknown' {
			right = "${op_type}(${right})"
		}
	}

	// Complex number support
	if left_type == 'PyComplex' && right_type != 'PyComplex' {
		right = "py_complex(f64(${right}), 0.0)"
	} else if right_type == 'PyComplex' && left_type != 'PyComplex' {
		left = "py_complex(f64(${left}), 0.0)"
	}

	if op == 'and' || op == 'or' {
		return eg.build_pythonic_bool_op(node, op == 'and')
	}

	match op {
		'@' { return "${left}.matmul(${right})" }
		'**' {
			eg.state.used_builtins['math.pow'] = true
			mut is_negative_literal := false
			if node.right is ast.UnaryOp && node.right.op.value == '-' {
				if node.right.operand is ast.Constant { is_negative_literal = true }
			} else if node.right is ast.Constant {
				val := node.right.value
				if val.starts_with('-') { is_negative_literal = true }
			}
			is_float_op := left_type == 'f64' || right_type == 'f64' || is_negative_literal
			if is_float_op {
				l_val := if left_type == 'int' { "f64(${left})" } else { left }
				r_val := if right_type == 'int' { "f64(${right})" } else { right }
				return "math.pow(${l_val}, ${r_val})"
			}
			return "int(math.powi(f64(${left}), ${right}))"
		}
		'//' {
			eg.state.used_builtins['math.floor'] = true
			if left_type in ['int', 'i64'] || right_type in ['int', 'i64'] {
				return "i64(math.floor(f64(${left}) / f64(${right})))"
			}
			return "math.floor(${left} / ${right})"
		}
		'%' {
			if left_type == '[]u8' || (node.left is ast.Constant && node.left.value.starts_with('b"')) {
				eg.state.used_builtins['py_bytes_format'] = true
				return eg.format_percent_bytes(left, node.right)
			}
			is_string_fmt := left_type == 'string' || left_type == 'LiteralString' || (node.left is ast.Constant && node.left.value.starts_with('"'))
			if is_string_fmt {
				eg.state.used_string_format = true
				// For simple literals without complex formatting, use V interpolation
				if node.left is ast.Constant {
					fmt_str := node.left.value.trim('\'"')
					if !fmt_str.contains('%%') && !fmt_str.contains('%(') && fmt_str.count('%') > 0 {
						if mapped := eg.map_python_percent_to_v_interpolation(fmt_str, node.right) {
							return mapped
						}
					}
				}
				return eg.format_percent_call(left, node.right)
			}
		}
		else {}
	}

	// Set operations
	if eg.is_set_type(left_type) && eg.is_set_type(right_type) {
		match op {
			'|' { eg.state.used_builtins['py_set_union'] = true return "py_set_union(${left}, ${right})" }
			'&' { eg.state.used_builtins['py_set_intersection'] = true return "py_set_intersection(${left}, ${right})" }
			'-' { eg.state.used_builtins['py_set_difference'] = true return "py_set_difference(${left}, ${right})" }
			'^' { eg.state.used_builtins['py_set_xor'] = true return "py_set_xor(${left}, ${right})" }
			else {}
		}
	}

	return "${left} ${op} ${right}"
}


fn (mut eg ExprGen) build_pythonic_bool_op(node ast.BinaryOp, is_and bool) string {
	left_type := eg.guess_type(node.left)
	right_type := eg.guess_type(node.right)
	
	l_val := eg.visit(node.left)
	r_val := eg.visit(node.right)
	
	// Idiomatic V 'or' block for Optional types
	if !is_and && (left_type.starts_with('?') || (left_type == 'Any' && l_val.contains(' as '))) {
		return "${l_val} or { ${r_val} }"
	}

	if left_type == 'bool' && right_type == 'bool' {
		l := eg.wrap_bool(node.left, false)
		r := eg.wrap_bool(node.right, false)
		return if is_and { "${l} && ${r}" } else { "${l} || ${r}" }
	}
	l_cond := eg.wrap_bool(node.left, false)
	
	mut l_expr := l_val
	mut r_expr := r_val
	if eg.state.current_assignment_type == 'Any' {
		if !l_expr.starts_with('Any(') && left_type != 'Any' {
			l_expr = if left_type.starts_with('?') { "Any(${l_expr}!)" } else { "Any(${l_expr})" }
		}
		if !r_expr.starts_with('Any(') && right_type != 'Any' {
			r_expr = if right_type.starts_with('?') { "Any(${r_expr}!)" } else { "Any(${r_expr})" }
		}
	}
	
	if is_and { return "if ${l_cond} { ${r_expr} } else { ${l_expr} }" }
	else { return "if ${l_cond} { ${l_expr} } else { ${r_expr} }" }
}

// build_truthiness_for_or builds the truthiness check for or/and Expressions
// with proper none handling, matching the mature pythontovlang transpiler.
fn (mut eg ExprGen) build_truthiness_for_or(node ast.Expression, is_or bool) string {
	v_type := eg.guess_type(node)
	expr := eg.visit(node)
	eprintln('DEBUG: build_truthiness_for_or expr=${expr} type=${v_type} is_or=${is_or}')
	
	// For Any type (sum type), use is NoneType check for proper none detection
	if v_type == 'Any' {
		return "(${expr} !is NoneType && ${expr} != 0)"
	}
	
	// For optional types
	if v_type.starts_with('?') {
		inner := v_type[1..]
		if is_collection_type(inner) {
			return "(${expr} != none && ${expr}!.len > 0)"
		}
		if is_numeric_type(inner) {
			return "(${expr} != none && ${expr}! != 0)"
		}
		if inner == 'string' || inner == 'LiteralString' {
			return "(${expr} != none && ${expr}!.len > 0)"
		}
		return "${expr} != none"
	}
	
	// For simple identifiers in `or` context, conservatively add none check
	if node is ast.Name {
		return "(${expr} !is NoneType && ${expr} != 0)"
	}
	
	// For strings and collections
	if is_collection_type(v_type) {
		return "${expr}.len > 0"
	}
	if is_numeric_type(v_type) {
		return "${expr} != 0"
	}
	if v_type == 'bool' {
		return expr
	}
	
	// Fallback to py_bool for unknown types
	eg.state.used_builtins['py_bool'] = true
	return "py_bool(${expr})"
}

fn (mut eg ExprGen) format_repeated_list_literal(list_node ast.List, len_node ast.Expression) string {
	len_expr := eg.visit(len_node)
	if list_node.elements.len == 0 {
		return "[]Any{len: ${len_expr}, init: none}"
	}
	init_node := list_node.elements[0]
	init_val := eg.visit(init_node)
	
	mut final_init := init_val
	if is_none_expr(init_node) {
		final_init = 'none'
		expected := eg.state.current_assignment_type
		mut elem_t := if expected.starts_with('[]') { expected[2..] } else { 'Any' }

		if eg.should_use_is_none_type(elem_t, init_node) {
			return "[]${elem_t}{len: ${len_expr}, init: NoneType{}}"
		}

		if !elem_t.starts_with('?') { elem_t = '?${elem_t}' }
		return "[]${elem_t}{len: ${len_expr}, init: none}"
	}

	match init_node {
		ast.List, ast.Tuple, ast.Dict, ast.Call, ast.BinaryOp {
			eg.state.used_builtins['py_repeat'] = true
			return "py_repeat(${final_init}, ${len_expr})"
		}
		else {}
	}
	v_list := eg.visit_list(list_node)
	return '(${v_list}).repeat(${len_expr})'
}

pub fn (mut eg ExprGen) visit_unary_op(node ast.UnaryOp) string {
	if node.op.value == 'not' {
		return eg.wrap_bool(node.operand, true)
	}
	operand := eg.visit(node.operand)
	return "${node.op.value}${operand}"
}

pub fn (mut eg ExprGen) visit_bool_op(node ast.BoolOp) string {
	if node.values.len < 2 {
		if node.values.len == 1 {
			return eg.visit(node.values[0])
		}
		return 'true'
	}
	
	op := node.op.value
	is_and := op == 'and'
	
	// Handle 2-value case
	if node.values.len == 2 {
		mut left := eg.visit(node.values[0])
		mut right := eg.visit(node.values[1])
		left_type := eg.guess_type(node.values[0])
		right_type := eg.guess_type(node.values[1])
		
		if left_type == 'bool' && right_type == 'bool' {
			return if is_and { "${left} && ${right}" } else { "${left} || ${right}" }
		}
		
		// Use build_truthiness_for_or for proper none handling
		l_cond := eg.build_truthiness_for_or(node.values[0], !is_and)
		mut l_val := left
		mut r_val := right
		
		if eg.state.current_assignment_type == 'Any' {
			if !l_val.starts_with('Any(') && left_type != 'Any' {
				l_val = if left_type.starts_with('?') { "Any(${l_val}!)" } else { "Any(${l_val})" }
			}
			if !r_val.starts_with('Any(') && right_type != 'Any' {
				r_val = if right_type.starts_with('?') { "Any(${r_val}!)" } else { "Any(${r_val})" }
			}
		}
		
		if is_and { return "(if ${l_cond} { ${r_val} } else { ${l_val} })" }
		else { return "(if ${l_cond} { ${l_val} } else { ${r_val} })" }
	}
	
	// Handle 3+ values using short-circuit pattern
	mut result := eg.visit(node.values[node.values.len - 1])
	for i := node.values.len - 2; i >= 0; i-- {
		v := node.values[i]
		// Use build_truthiness_for_or for proper none handling
		cond := eg.build_truthiness_for_or(v, !is_and)
		mut v_val := eg.visit(v)
		if eg.state.current_assignment_type == 'Any' {
			v_type := eg.guess_type(v)
			if !v_val.starts_with('Any(') && v_type != 'Any' {
				v_val = if v_type.starts_with('?') { "Any(${v_val}!)" } else { "Any(${v_val})" }
			}
		}
		if is_and {
			result = "(if ${cond} { ${result} } else { ${v_val} })"
		} else {
			result = "(if ${cond} { ${v_val} } else { ${result} })"
		}
	}
	return result
}

pub fn (mut eg ExprGen) visit_compare(node ast.Compare) string {
	mut comps := []string{cap: node.comparators.len + 1}
	comps << eg.visit(node.left)
	for c in node.comparators { comps << eg.visit(c) }

	if node.ops.len == 1 && comps.len == 2 {
		return eg.translate_single_comparison(comps[0], node.ops[0].value, comps[1], node.left, node.comparators[0])
	}

	mut parts := []string{}
	for i, op in node.ops {
		if i + 1 >= comps.len { break }
		left_node := if i == 0 { node.left } else { node.comparators[i-1] }
		right_node := node.comparators[i]
		res := eg.translate_single_comparison(comps[i], op.value, comps[i + 1], left_node, right_node)
		parts << "(${res})"
	}
	return parts.join(' && ')
}

fn (mut eg ExprGen) translate_single_comparison(left string, op string, right string, left_expr ast.Expression, right_expr ast.Expression) string {
	left_type := eg.guess_type(left_expr)
	right_type := eg.guess_type(right_expr)

	if op in ['is', '=='] && is_none_expr(right_expr) {
		if eg.should_use_is_none_type(left_type, left_expr) { return "(${left} is NoneType)" }
		return "${left} == none"
	}
	if op in ['is not', '!='] && is_none_expr(right_expr) {
		if eg.should_use_is_none_type(left_type, left_expr) { return "(${left} !is NoneType)" }
		return "${left} != none"
	}
	if op in ['is', '=='] && is_none_expr(left_expr) {
		if eg.should_use_is_none_type(right_type, right_expr) { return "(${right} is NoneType)" }
		return "none == ${right}"
	}
	if op in ['is not', '!='] && is_none_expr(left_expr) {
		if eg.should_use_is_none_type(right_type, right_expr) { return "(${right} !is NoneType)" }
		return "none != ${right}"
	}

	if op == 'is' {
		eg.state.used_builtins['py_is_identical'] = true
		return "py_is_identical(${left}, ${right})"
	}
	if op == 'is not' {
		eg.state.used_builtins['py_is_identical'] = true
		return "!py_is_identical(${left}, ${right})"
	}

	if op == 'in' || op == 'not in' {
		prefix := if op == 'not in' { '!' } else { '' }
		if is_none_expr(left_expr) {
			if right_type.starts_with('map[') { return "${prefix}(none in ${right})" }
			return "${prefix}${right}.any(it == none)"
		}
		if op == 'not in' { return '!(${left} in ${right})' }
		return "${left} ${op} ${right}"
	}

	if eg.is_set_type(left_type) && eg.is_set_type(right_type) {
		match op {
			'<=' { eg.state.used_builtins['py_set_subset'] = true return "py_set_subset(${left}, ${right})" }
			'<' { eg.state.used_builtins['py_set_strict_subset'] = true return "py_set_strict_subset(${left}, ${right})" }
			'>=' { eg.state.used_builtins['py_set_superset'] = true return "py_set_superset(${left}, ${right})" }
			'>' { eg.state.used_builtins['py_set_strict_superset'] = true return "py_set_strict_superset(${left}, ${right})" }
			else {}
		}
	}

	v_op := match op {
		'is' { '==' }
		'is not' { '!=' }
		'not in' { return '!(${left} in ${right})' }
		else { op }
	}
	return "${left} ${v_op} ${right}"
}

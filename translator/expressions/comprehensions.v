module expressions

import ast

fn get_int_const(expr ast.Expression) (int, bool) {
	if expr is ast.Constant {
		return expr.value.int(), true
	} else if expr is ast.UnaryOp {
		if expr.op.value == '-' {
			if expr.operand is ast.Constant {
				return -expr.operand.value.int(), true
			}
		} else if expr.op.value == '+' {
			if expr.operand is ast.Constant {
				return expr.operand.value.int(), true
			}
		}
	}
	return 0, false
}

fn (mut eg ExprGen) infer_generator_target_types(gen ast.Comprehension) {
	iter_type := eg.guess_type(gen.iter)
	mut elt_type := 'Any'
	if iter_type.starts_with('[]') {
		elt_type = iter_type[2..]
	} else if iter_type.starts_with('map[') {
		elt_type = 'string' // iteration over dict keys
	} else if iter_type.starts_with('datatypes.Set[') {
		elt_type = iter_type[14..iter_type.len - 1]
	}

	if gen.iter is ast.Call {
		iter_call := gen.iter
		if iter_call.func is ast.Name {
			if iter_call.func.id in ['range', 'xrange'] {
				elt_type = 'int'
			} else if iter_call.func.id == 'enumerate' {
				elt_type = 'PyEnumerateItem'
				if gen.target is ast.Tuple && gen.target.elements.len >= 2 {
					eg.infer_target_types_from_val(gen.target.elements[0], 'int')
					// Index 1 is the item
					if iter_call.args.len > 0 {
						arg_type := eg.guess_type(iter_call.args[0])
						if arg_type.starts_with('[]') {
							eg.infer_target_types_from_val(gen.target.elements[1], arg_type[2..])
						}
					}
					return
				}
			} else if iter_call.func.id == 'zip' && gen.target is ast.Tuple {
				for i, elt in gen.target.elements {
					if i < iter_call.args.len {
						arg_type := eg.guess_type(iter_call.args[i])
						if arg_type.starts_with('[]') {
							eg.infer_target_types_from_val(elt, arg_type[2..])
						}
					}
				}
				return
			} else if iter_call.func.id == 'zip' {
				elt_type = 'PyZipItem'
			}
		}
	}

	eg.infer_target_types_from_val(gen.target, elt_type)
}

fn (mut eg ExprGen) infer_target_types_from_val(target ast.Expression, val_type string) {
	if target is ast.Name {
		eg.analyzer.type_map[target.id] = val_type
	} else if target is ast.Tuple && val_type.contains(',') {
		// Try to split val_type if it is a tuple/zip item
		// This is a simplification
	} else if target is ast.Tuple {
		for elt in target.elements {
			if elt is ast.Name {
				eg.analyzer.type_map[elt.id] = 'Any' // fallback
			}
		}
	}
}

pub fn (mut eg ExprGen) emit_generators(generators []ast.Comprehension, body_callback fn (mut ExprGen)) {
	if generators.len == 0 {
		body_callback(mut eg)
		return
	}

	gen := generators[0]
	rest := generators[1..]
	eg.infer_generator_target_types(gen)

	if gen.is_async {
		eg.emit('// async comprehension requires manual review')
	}

	mut iter_expr := eg.visit(gen.iter)
	mut target := eg.visit(gen.target)
	mut is_enumerate := false

	if gen.iter is ast.Call {
		iter_call := gen.iter
		if iter_call.func is ast.Name {
			if iter_call.func.id == 'enumerate' {
				is_enumerate = true
				if iter_call.args.len > 0 {
					iter_expr = eg.visit(iter_call.args[0])
				}
				if gen.target is ast.Tuple && target.starts_with('[') && target.ends_with(']') {
					target = target[1..target.len - 1]
				}
			}

			if iter_call.func.id == 'zip' {
				eg.state.zip_counter++
				zip_id := eg.state.zip_counter
				mut it_names := []string{}
				for i, arg in iter_call.args {
					it_name := 'py_zip_it${i + 1}_${zip_id}'
					eg.emit('${it_name} := ${eg.visit(arg)}')
					it_names << it_name
				}
				idx_name := 'py_i_${zip_id}'
				v1_name := 'py_v1_${zip_id}'
				eg.emit('for ${idx_name}, ${v1_name} in ${it_names[0]} {')
				eg.state.indent_level++
				mut v_names := [v1_name]
				for i := 1; i < it_names.len; i++ {
					eg.emit('if ${idx_name} >= ${it_names[i]}.len { break }')
					vi_name := 'py_v${i + 1}_${zip_id}'
					eg.emit('${vi_name} := ${it_names[i]}[${idx_name}]')
					v_names << vi_name
				}
				if gen.target is ast.Tuple {
					for i, elt in gen.target.elements {
						eg.emit('${eg.visit(elt)} := ${v_names[i]}')
					}
				} else {
					target_str := eg.visit(gen.target)
					eg.emit('${target_str} := [${v_names.join(', ')}]')
				}

				for if_expr in gen.ifs {
					eg.emit('if ${eg.wrap_bool(if_expr, false)} {')
					eg.state.indent_level++
				}
				eg.emit_generators(rest, body_callback)
				for _ in gen.ifs {
					eg.state.indent_level--
					eg.emit('}')
				}
				eg.state.indent_level--
				eg.emit('}')
				return
			}

			if iter_call.func.id in ['range', 'xrange'] {
				mut start := '0'
				mut stop := '0'
				mut step := '1'
				if iter_call.args.len == 1 {
					stop = eg.visit(iter_call.args[0])
				} else if iter_call.args.len >= 2 {
					start = eg.visit(iter_call.args[0])
					stop = eg.visit(iter_call.args[1])
					if iter_call.args.len > 2 {
						step = eg.visit(iter_call.args[2])
					}
				}
				if step == '1' {
					if start == '0' {
						eg.emit('for ${target} in 0..${stop} {')
					} else {
						eg.emit('for ${target} in ${start}..${stop} {')
					}
				} else {
					op := if step.starts_with('-') { '>' } else { '<' }
					eg.emit('for ${target} := ${start}; ${target} ${op} ${stop}; ${target} += ${step} {')
				}
				eg.state.indent_level++
				for if_expr in gen.ifs {
					eg.emit('if ${eg.wrap_bool(if_expr, false)} {')
					eg.state.indent_level++
				}
				eg.emit_generators(rest, body_callback)
				for _ in gen.ifs {
					eg.state.indent_level--
					eg.emit('}')
				}
				eg.state.indent_level--
				eg.emit('}')
				return
			}
		}
	}

	if gen.target is ast.Tuple && !is_enumerate {
		val_name := 'py_comp_val_${eg.state.unique_id_counter + 1}'
		eg.emit('for ${val_name} in ${iter_expr} {')
		eg.state.indent_level++
		for i, elt in gen.target.elements {
			eg.emit('${eg.visit(elt)} := ${val_name}[${i}]')
		}
	} else {
		eg.emit('for ${target} in ${iter_expr} {')
		eg.state.indent_level++
	}

	for if_expr in gen.ifs {
		eg.emit('if ${eg.wrap_bool(if_expr, false)} {')
		eg.state.indent_level++
	}

	eg.emit_generators(rest, body_callback)

	for _ in gen.ifs {
		eg.state.indent_level--
		eg.emit('}')
	}
	eg.state.indent_level--
	eg.emit('}')
}

pub fn (mut eg ExprGen) visit_list_comp(node ast.ListComp, target_var string) ?string {
	mut target := target_var
	if target.len == 0 {
		eg.state.unique_id_counter++
		target = 'py_comp_${eg.state.unique_id_counter}'
	}

	eg.infer_generator_target_types(node.generators[0])
	mut elt_type := eg.guess_type(node.elt)
	if elt_type == 'unknown' {
		elt_type = 'int'
	}
	mut cap_str := ''
	if node.generators.len == 1 && node.generators[0].ifs.len == 0 {
		gen := node.generators[0]
		if gen.iter is ast.Call {
			call := gen.iter
			if call.func is ast.Name && call.func.id in ['range', 'xrange'] {
				if call.args.len == 1 {
					cap_str = 'cap: ${eg.visit(call.args[0])}'
				} else if call.args.len == 2 {
					start_val, is_start_const := get_int_const(call.args[0])
					stop_val, is_stop_const := get_int_const(call.args[1])
					if is_start_const && is_stop_const {
						cap_str = 'cap: ${stop_val - start_val}'
					} else {
						cap_str = 'cap: ${eg.visit(call.args[1])}'
					}
				} else if call.args.len >= 3 {
					start_val, is_start_const := get_int_const(call.args[0])
					stop_val, is_stop_const := get_int_const(call.args[1])
					step_val, is_step_const := get_int_const(call.args[2])
					if is_start_const && is_stop_const && is_step_const {
						if step_val != 0 {
							diff := if step_val > 0 {
								stop_val - start_val
							} else {
								start_val - stop_val
							}
							abs_step := if step_val > 0 { step_val } else { -step_val }
							if diff > 0 {
								cap_str = 'cap: ${(diff + abs_step - 1) / abs_step}'
							} else {
								cap_str = 'cap: 0'
							}
						}
					}
				}
			}
		} else if gen.iter is ast.List {
			cap_str = 'cap: ${gen.iter.elements.len}'
		} else if gen.iter is ast.Tuple {
			cap_str = 'cap: ${gen.iter.elements.len}'
		}
	}
	cap_suffix := if cap_str.len > 0 { '{${cap_str}}' } else { '{}' }
	eg.emit('mut ${target} := []${elt_type}${cap_suffix}')
	eg.emit_generators(node.generators, fn [node, target] (mut eg ExprGen) {
		eg.emit('${target} << ${eg.visit(node.elt)}')
	})
	return target
}

pub fn (mut eg ExprGen) visit_generator_exp_inline(node ast.GeneratorExp) ?string {
	if node.generators.len == 1 && node.generators[0].ifs.len == 0 {
		gen := node.generators[0]
		if gen.target is ast.Name {
			eg.infer_generator_target_types(gen)
			target_id := gen.target.id
			iter_expr := eg.visit(gen.iter)

			// Remap target_id to 'it' for V map
			prev_remap := eg.state.name_remap[target_id] or { '' }
			eg.state.name_remap[target_id] = 'it'
			elt_expr := eg.visit(node.elt)
			if prev_remap.len > 0 {
				eg.state.name_remap[target_id] = prev_remap
			} else {
				eg.state.name_remap.delete(target_id)
			}

			return '${iter_expr}.map(${elt_expr})'
		}
	}
	return none
}

pub fn (mut eg ExprGen) visit_generator_exp(node ast.GeneratorExp, target_var string) ?string {
	if target_var.len == 0 {
		if res := eg.visit_generator_exp_inline(node) {
			return res
		}
	}
	list_like := ast.ListComp{
		token:      node.token
		elt:        node.elt
		generators: node.generators
	}
	return eg.visit_list_comp(list_like, target_var)
}

pub fn (mut eg ExprGen) visit_dict_comp(node ast.DictComp, target_var string) ?string {
	mut target := target_var
	if target.len == 0 {
		eg.state.unique_id_counter++
		target = 'py_comp_${eg.state.unique_id_counter}'
	}
	eg.infer_generator_target_types(node.generators[0])
	key_type := eg.guess_type(node.key)
	val_type := eg.guess_type(node.value)
	eg.emit('mut ${target} := map[${key_type}]${val_type}{}')
	eg.emit_generators(node.generators, fn [node, target] (mut eg ExprGen) {
		eg.emit('${target}[${eg.visit(node.key)}] = ${eg.visit(node.value)}')
	})
	return target
}

pub fn (mut eg ExprGen) visit_set_comp(node ast.SetComp, target_var string) ?string {
	mut target := target_var
	if target.len == 0 {
		eg.state.unique_id_counter++
		target = 'py_comp_${eg.state.unique_id_counter}'
	}
	eg.infer_generator_target_types(node.generators[0])
	key_type := eg.guess_type(node.elt)
	eg.emit('mut ${target} := datatypes.Set[${key_type}]{}')
	eg.emit_generators(node.generators, fn [node, target] (mut eg ExprGen) {
		eg.emit('${target}.add(${eg.visit(node.elt)})')
	})
	return target
}

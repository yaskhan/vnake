module mypy

fn new_test_semantic_analyzer() &SemanticAnalyzer {
	options := Options{}
	errors := new_errors(options)
	plugin := new_plugin(options)
	return new_semantic_analyzer(map[string]&MypyFile{}, errors, plugin, options)
}

fn prepare_test_module(mut sa SemanticAnalyzer, module_name string) &MypyFile {
	mut file := &MypyFile{
		fullname:            module_name
		path:                '${module_name}.py'
		names:               SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
		defs:                []Statement{}
		future_import_flags: map[string]bool{}
	}
	// Register the heap-allocated module before visiting it so any saved analyzer references
	// (for example cur_mod_node during later type analysis) continue to point at owned storage.
	sa.modules[module_name] = file
	sa.visit_mypy_file(mut file) or { panic(err.msg) }
	return file
}

fn test_annotation_head_name_handles_simple_qualified_and_non_unbound_types() {
	assert annotation_head_name(MypyTypeNode(UnboundType{
		name: 'Final'
	})) == 'Final'
	assert annotation_head_name(MypyTypeNode(UnboundType{
		name: 'typing.ClassVar'
	})) == 'ClassVar'
	assert annotation_head_name(MypyTypeNode(AnyType{
		type_of_any: .special_form
	})) == ''
}

fn test_unwrap_assignment_annotation_removes_nested_wrappers() {
	nested := MypyTypeNode(UnboundType{
		name: 'Final'
		args: [MypyTypeNode(UnboundType{
			name: 'typing.ClassVar'
			args: [MypyTypeNode(UnboundType{
				name: 'builtins.int'
			})]
		})]
	})
	unwrapped := unwrap_assignment_annotation(nested)
	match unwrapped {
		UnboundType {
			assert unwrapped.name == 'builtins.int'
		}
		else {
			panic('expected innermost unbound type')
		}
	}
}

fn test_flatten_lvalues_flattens_nested_tuple_and_list_targets() {
	sa := new_test_semantic_analyzer()
	flattened := sa.flatten_lvalues([
		Expression(TupleExpr{
			items: [
				Expression(NameExpr{
					name: 'a'
				}),
				Expression(ListExpr{
					items: [
						Expression(NameExpr{
							name: 'b'
						}),
						Expression(NameExpr{
							name: 'c'
						}),
					]
				}),
			]
		}),
		Expression(NameExpr{
			name: 'd'
		}),
	])
	assert flattened.len == 4
	assert (flattened[0] as NameExpr).name == 'a'
	assert (flattened[1] as NameExpr).name == 'b'
	assert (flattened[2] as NameExpr).name == 'c'
	assert (flattened[3] as NameExpr).name == 'd'
}

fn test_recurse_into_functions_defaults_to_true() {
	sa := new_test_semantic_analyzer()
	assert sa.recurse_into_functions()
}

fn test_recurse_into_functions_can_skip_top_level_bodies() {
	mut sa := new_test_semantic_analyzer()
	sa.recurse_into_function_bodies = false
	assert !sa.recurse_into_functions()
}

fn test_recurse_into_functions_keeps_nested_function_analysis_enabled() {
	mut sa := new_test_semantic_analyzer()
	sa.recurse_into_function_bodies = false
	sa.function_stack << FuncItem(FuncDef{
		name: 'outer'
	})
	assert sa.recurse_into_functions()
}

fn test_visit_import_from_records_future_import_flags() {
	mut sa := new_test_semantic_analyzer()
	mut future_module := &MypyFile{
		fullname:            '__future__'
		path:                '__future__.py'
		names:               SymbolTable{
			symbols: {
				'annotations': SymbolTableNode{
					kind: gdef
				}
				'division':    SymbolTableNode{
					kind: gdef
				}
			}
		}
		future_import_flags: map[string]bool{}
	}
	sa.modules['__future__'] = future_module

	mut file := MypyFile{
		fullname:            'pkg.mod'
		path:                'pkg/mod.py'
		names:               SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
		defs:                [
			Statement(ImportFrom{
				id:    '__future__'
				names: [
					ImportAlias{
						name: 'annotations'
					},
					ImportAlias{
						name: 'division'
					},
				]
			}),
		]
		future_import_flags: map[string]bool{}
	}

	sa.visit_mypy_file(mut file) or { panic(err.msg) }

	assert sa.is_future_flag_set('annotations')
	assert sa.is_future_flag_set('division')
	assert file.future_import_flags['annotations']
	assert file.future_import_flags['division']
}

fn test_prepare_file_restores_saved_future_import_flags() {
	mut sa := new_test_semantic_analyzer()
	mut file := MypyFile{
		fullname:            'pkg.mod'
		path:                'pkg/mod.py'
		names:               SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
		future_import_flags: {
			'annotations': true
		}
	}

	sa.prepare_file(mut file)

	assert sa.is_future_flag_set('annotations')
	assert !sa.is_future_flag_set('division')
}

fn test_visit_placeholder_node_marks_analysis_as_deferred_and_incomplete() {
	mut sa := new_test_semantic_analyzer()
	mut placeholder := PlaceholderNode{
		fullname: 'pkg.Missing'
		base:     NodeBase{
			ctx: Context{
				line:   3
				column: 1
			}
		}
	}

	sa.visit_placeholder_node(mut placeholder) or { panic(err.msg) }

	assert sa.deferred
	assert sa.incomplete
	assert sa.missing_names.len > 0
	assert incomplete_ref_marker in sa.missing_names.last()
}

fn test_visit_type_info_traverses_class_body_and_restores_class_scope() {
	mut sa := new_test_semantic_analyzer()
	sa.errors.set_file('test.py', 'pkg.mod')

	mut defn := &ClassDef{
		name: 'Box'
		defs: Block{
			body: [
				Statement(ExpressionStmt{
					expr: Expression(NameExpr{
						name: 'missing'
						base: NodeBase{
							ctx: Context{
								line:   7
								column: 2
							}
						}
					})
				}),
			]
		}
	}
	mut symtab := SymbolTable{}
	mut info := new_type_info(mut symtab, defn, 'pkg.mod')
	info.fullname = 'pkg.mod.Box'
	defn.info = info

	sa.visit_type_info(mut info) or { panic(err.msg) }

	assert sa.cur_type == none
	infos := sa.errors.error_info_map['test.py'] or { panic('expected collected error') }
	assert infos.len == 1
	assert infos[0].message == 'Name "missing" is not defined'
}

fn test_visit_type_info_without_defn_uses_class_scope_for_members() {
	mut sa := new_test_semantic_analyzer()
	sa.cur_mod_id = 'pkg.mod'

	mut method := FuncDef{
		name: 'method'
		body: Block{
			body: []Statement{}
		}
	}
	mut info := TypeInfo{
		fullname:    'pkg.mod.Box'
		module_name: 'pkg.mod'
		name:        'Box'
		names:       SymbolTable{
			symbols: {
				'method': SymbolTableNode{
					kind: mdef
					node: SymbolNodeRef(method)
				}
			}
		}
	}

	sa.visit_type_info(mut info) or { panic(err.msg) }

	assert sa.cur_type == none
	sym := info.names.symbols['method'] or { panic('expected method symbol') }
	node := sym.node or { panic('expected method node') }
	match node {
		FuncDef {
			assert node.fullname == 'pkg.mod.Box.method'
			method_info := node.info or { panic('expected method to be analyzed in class scope') }
			assert method_info.fullname == 'pkg.mod.Box'
		}
		else {
			panic('expected FuncDef method node')
		}
	}
}

fn test_visit_assignment_stmt_processes_final_annotation_and_value() {
	mut sa := new_test_semantic_analyzer()
	mut file := MypyFile{
		fullname:            'pkg.mod'
		path:                'pkg/mod.py'
		names:               SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
		defs:                [
			Statement(AssignmentStmt{
				lvalues: [Expression(NameExpr{
					name: 'answer'
				})]
				rvalue:          Expression(IntExpr{
					value: 42
				})
				type_annotation: MypyTypeNode(UnboundType{
					name: 'Final'
					args: [MypyTypeNode(UnboundType{
						name: 'builtins.int'
					})]
				})
			}),
		]
		future_import_flags: map[string]bool{}
	}

	sa.visit_mypy_file(mut file) or { panic(err.msg) }

	sym := file.names.symbols['answer'] or { panic('expected answer symbol') }
	node := sym.node or { panic('expected answer node') }
	analyzed_stmt := file.defs[0] as AssignmentStmt
	match node {
		Var {
			assert node.is_final
			assert node.has_explicit_value
			assert node.type_ != none
			fval := node.final_value or { panic('expected final value to be stored') }
			match fval {
				IntExpr {
					assert fval.value == 42
				}
				else {
					panic('expected int final value')
				}
			}
		}
		else {
			panic('expected Var symbol for final assignment')
		}
	}
	analyzed_type := analyzed_stmt.type_annotation or { panic('expected normalized annotation') }
	if analyzed_type is UnboundType {
		assert analyzed_type.name != 'Final'
	}
}

fn test_visit_assignment_stmt_processes_bare_final_annotation_and_infers_value_type() {
	mut sa := new_test_semantic_analyzer()
	mut file := MypyFile{
		fullname:            'pkg.mod'
		path:                'pkg/mod.py'
		names:               SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
		defs:                [
			Statement(AssignmentStmt{
				lvalues: [Expression(NameExpr{
					name: 'count'
				})]
				rvalue:          Expression(IntExpr{
					value: 200
				})
				type_annotation: MypyTypeNode(UnboundType{
					name: 'Final'
				})
			}),
		]
		future_import_flags: map[string]bool{}
	}

	sa.visit_mypy_file(mut file) or { panic(err.msg) }

	sym := file.names.symbols['count'] or { panic('expected count symbol') }
	node := sym.node or { panic('expected count node') }
	analyzed_stmt := file.defs[0] as AssignmentStmt
	match node {
		Var {
			assert node.is_final
			assert node.has_explicit_value
			typ := node.type_ or { panic('expected inferred bare Final type') }
			match typ {
				Instance {
					if info := typ.typ {
						assert info.fullname == 'builtins.int'
					} else {
						assert typ.type_name == 'builtins.int' || typ.type_fullname == 'builtins.int'
					}
				}
				else {
					panic('expected inferred builtins.int type for bare Final assignment')
				}
			}
			fval := node.final_value or { panic('expected bare Final value to be stored') }
			match fval {
				IntExpr {
					assert fval.value == 200
				}
				else {
					panic('expected int final value for bare Final assignment')
				}
			}
		}
		else {
			panic('expected Var symbol for bare final assignment')
		}
	}
	analyzed_type := analyzed_stmt.type_annotation or { panic('expected normalized bare Final annotation') }
	if analyzed_type is UnboundType {
		assert analyzed_type.name != 'Final'
	}
}
fn test_visit_assignment_stmt_marks_classvar_in_class_scope() {
	mut sa := new_test_semantic_analyzer()
	prepare_test_module(mut sa, 'pkg.mod')
	sa.cur_mod_id = 'pkg.mod'
	sa.globals = SymbolTable{
		symbols: map[string]SymbolTableNode{}
	}
	sa.locals = [?SymbolTable(SymbolTable{
		symbols: map[string]SymbolTableNode{}
	})]
	sa.scope_stack = [scope_class]
	sa.cur_type = &TypeInfo{
		name:        'Box'
		fullname:    'pkg.mod.Box'
		module_name: 'pkg.mod'
		names:       SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
	}

	mut stmt := AssignmentStmt{
		lvalues: [Expression(NameExpr{
			name: 'value'
		})]
		rvalue:          Expression(IntExpr{
			value: 1
		})
		type_annotation: MypyTypeNode(UnboundType{
			name: 'ClassVar'
			args: [MypyTypeNode(UnboundType{
				name: 'builtins.int'
			})]
		})
	}

	sa.visit_assignment_stmt(mut stmt) or { panic(err.msg) }

	lvalue := stmt.lvalues[0] as NameExpr
	node := lvalue.node or { panic('expected bound class variable') }
	match node {
		Var {
			assert node.is_classvar
			assert node.type_ != none
		}
		else {
			panic('expected Var node for class variable')
		}
	}
	analyzed_type := stmt.type_annotation or { panic('expected normalized ClassVar annotation') }
	if analyzed_type is UnboundType {
		assert analyzed_type.name != 'ClassVar'
	}
}

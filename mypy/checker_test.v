module mypy

fn new_test_type_checker() &TypeChecker {
	options := Options{}
	errors := new_errors(options)
	tree := &MypyFile{
		path:     'test.py'
		fullname: '__main__'
		names:    SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
	}
	plugin := new_plugin(options)
	return new_type_checker(errors, map[string]&MypyFile{}, options, tree, tree.path, plugin)
}

fn new_test_instance(fullname string) Instance {
	info := &TypeInfo{
		name:     fullname
		fullname: fullname
	}
	return Instance{
		typ:           info
		type_:         info
		type_name:     fullname
		type_fullname: fullname
	}
}

fn set_root_type(mut tc TypeChecker, name string, typ MypyTypeNode) {
	tc.type_maps[0][name] = typ
}

fn new_test_module(fullname string) &MypyFile {
	return &MypyFile{
		path:     '${fullname}.py'
		fullname: fullname
		names:    SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
	}
}

fn test_find_isinstance_check_narrows_union_types() {
	mut tc := new_test_type_checker()
	int_type := MypyTypeNode(new_test_instance('builtins.int'))
	str_type := MypyTypeNode(new_test_instance('builtins.str'))
	declared := MypyTypeNode(UnionType{
		items: [int_type, str_type]
	})

	x_var := Var{
		name:     'x'
		fullname: '__main__.x'
		type_:    declared
	}
	x_expr := NameExpr{
		name:     'x'
		fullname: '__main__.x'
		node:     MypyNode(x_var)
	}
	set_root_type(mut tc, 'x', declared)

	int_info := TypeInfo{
		name:     'int'
		fullname: 'builtins.int'
	}
	int_expr := NameExpr{
		name:     'int'
		fullname: 'builtins.int'
		node:     MypyNode(int_info)
	}
	isinstance_expr := Expression(CallExpr{
		callee:    Expression(NameExpr{name: 'isinstance', fullname: 'builtins.isinstance'})
		args:      [Expression(x_expr), Expression(int_expr)]
		arg_kinds: [.arg_pos, .arg_pos]
	})

	if_map, else_map := tc.find_isinstance_check(isinstance_expr)

	narrowed := if_map['x'] or { panic('expected narrowed type when isinstance check passes') }
	narrowed_proper := get_proper_type(narrowed)
	narrowed_inst := narrowed_proper as Instance
	assert narrowed_inst.type_name == 'builtins.int'

	remaining := else_map['x'] or { panic('expected remaining type when isinstance check fails') }
	remaining_proper := get_proper_type(remaining)
	remaining_inst := remaining_proper as Instance
	assert remaining_inst.type_name == 'builtins.str'
}

fn test_visit_assert_stmt_applies_isinstance_narrowing() {
	mut tc := new_test_type_checker()
	int_type := MypyTypeNode(new_test_instance('builtins.int'))
	str_type := MypyTypeNode(new_test_instance('builtins.str'))
	declared := MypyTypeNode(UnionType{
		items: [int_type, str_type]
	})

	x_var := Var{
		name:     'x'
		fullname: '__main__.x'
		type_:    declared
	}
	x_expr := NameExpr{
		name:     'x'
		fullname: '__main__.x'
		node:     MypyNode(x_var)
	}
	set_root_type(mut tc, 'x', declared)

	int_info := TypeInfo{
		name:     'int'
		fullname: 'builtins.int'
	}
	int_expr := NameExpr{
		name:     'int'
		fullname: 'builtins.int'
		node:     MypyNode(int_info)
	}
	mut stmt := AssertStmt{
		expr: Expression(CallExpr{
			callee:    Expression(NameExpr{name: 'isinstance', fullname: 'builtins.isinstance'})
			args:      [Expression(x_expr), Expression(int_expr)]
			arg_kinds: [.arg_pos, .arg_pos]
		})
	}

	tc.visit_assert_stmt(mut stmt) or { panic(err.msg) }

	narrowed := tc.binder.get('x') or { panic('expected binder narrowing for x') }
	narrowed_proper := get_proper_type(narrowed)
	narrowed_inst := narrowed_proper as Instance
	assert narrowed_inst.type_name == 'builtins.int'
}

fn test_lookup_resolves_active_class_globals_builtins_and_modules() {
	mut tc := new_test_type_checker()
	mut builtins := new_test_module('builtins')
	builtins.names.symbols['len'] = SymbolTableNode{
		kind: gdef
	}
	tc.modules['builtins'] = builtins

	tc.globals.symbols['answer'] = SymbolTableNode{
		kind: gdef
	}

	mut info := &TypeInfo{
		name:     'Box'
		fullname: '__main__.Box'
		names:    SymbolTable{
			symbols: {
				'value': SymbolTableNode{
					kind: mdef
				}
			}
		}
	}
	tc.active_type = info

	assert tc.lookup('value').kind == mdef
	assert tc.lookup('answer').kind == gdef
	assert tc.lookup('len').kind == gdef

	mut pkg := new_test_module('pkg')
	tc.modules['pkg'] = pkg
	pkg_symbol := tc.lookup('pkg')
	pkg_node := pkg_symbol.node or { panic('expected module lookup to return module node') }
	assert pkg_node is MypyFile
}

fn test_lookup_qualified_and_lookup_typeinfo_follow_module_symbols() {
	mut tc := new_test_type_checker()
	mut pkg := new_test_module('pkg')
	mut method := FuncDef{
		name:     'method'
		fullname: 'pkg.Box.method'
	}
	mut info := &TypeInfo{
		name:     'Box'
		fullname: 'pkg.Box'
		names:    SymbolTable{
			symbols: {
				'method': SymbolTableNode{
					kind: mdef
					node: SymbolNodeRef(method)
				}
			}
		}
	}
	pkg.names.symbols['Box'] = SymbolTableNode{
		kind: gdef
		node: SymbolNodeRef(*info)
	}
	tc.modules['pkg'] = pkg

	box_symbol := tc.lookup_qualified('pkg.Box')
	box_node := box_symbol.node or { panic('expected pkg.Box to resolve to a class node') }
	assert box_node is TypeInfo

	method_symbol := tc.lookup_qualified('pkg.Box.method')
	method_node := method_symbol.node or { panic('expected pkg.Box.method to resolve to a method node') }
	assert method_node is FuncDef

	resolved := tc.lookup_typeinfo('pkg.Box')
	assert resolved.fullname == 'pkg.Box'
	assert resolved.name == 'Box'
}

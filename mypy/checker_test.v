module mypy

fn new_test_type_checker() &TypeChecker {
	options := Options{}
	errors := new_errors(options)
	tree := &MypyFile{
		path:     'test.py'
		fullname: '__main__'
		names:    SymbolTable{}
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
		node:     SymbolNodeRef(x_var)
	}
	tc.type_maps.last()['x'] = declared

	int_info := TypeInfo{
		name:     'int'
		fullname: 'builtins.int'
	}
	int_expr := NameExpr{
		name:     'int'
		fullname: 'builtins.int'
		node:     SymbolNodeRef(int_info)
	}
	isinstance_expr := Expression(CallExpr{
		callee:    Expression(NameExpr{name: 'isinstance', fullname: 'builtins.isinstance'})
		args:      [Expression(x_expr), Expression(int_expr)]
		arg_kinds: [.arg_pos, .arg_pos]
	})

	if_map, else_map := tc.find_isinstance_check(isinstance_expr)

	narrowed := if_map['x'] or { panic('expected positive narrowing for x') }
	assert narrowed is Instance
	assert (narrowed as Instance).type_name == 'builtins.int'

	remaining := else_map['x'] or { panic('expected negative narrowing for x') }
	assert remaining is Instance
	assert (remaining as Instance).type_name == 'builtins.str'
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
		node:     SymbolNodeRef(x_var)
	}
	tc.type_maps.last()['x'] = declared

	int_info := TypeInfo{
		name:     'int'
		fullname: 'builtins.int'
	}
	int_expr := NameExpr{
		name:     'int'
		fullname: 'builtins.int'
		node:     SymbolNodeRef(int_info)
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
	assert narrowed is Instance
	assert (narrowed as Instance).type_name == 'builtins.int'
}

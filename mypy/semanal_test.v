module mypy

fn new_test_semantic_analyzer() SemanticAnalyzer {
	options := Options{}
	errors := new_errors(options)
	plugin := new_plugin(options)
	return *new_semantic_analyzer(map[string]&MypyFile{}, errors, plugin, options)
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

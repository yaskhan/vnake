module mypy

fn new_test_semantic_analyzer() SemanticAnalyzer {
	options := Options{}
	errors := new_errors(options)
	plugin := new_plugin(options)
	return new_semantic_analyzer(map[string]&MypyFile{}, errors, plugin, options)
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

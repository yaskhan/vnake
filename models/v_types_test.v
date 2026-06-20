module models

fn test_map_basic_type() {
	assert map_basic_type('int') == 'int'
	assert map_basic_type('builtins.str') == 'string'
	assert map_basic_type('typing.List') == '[]Any'
	assert map_basic_type('typing_extensions.TypeForm') == 'Any'
	assert map_basic_type('  int  ') == 'int'
	assert map_basic_type('MyClass') == 'MyClass'
	assert map_basic_type('') == ''
}

fn test_map_python_type_to_v() {
	empty_fn := fn (a string, b string) string { return '' }
	empty_lit := fn (a []string) string { return '' }
	empty_tup := fn (a string) string { return '' }

	assert map_python_type_to_v('int', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'int'
	assert map_python_type_to_v('[]int', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == '[]int'
	assert map_python_type_to_v('map[string]int', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'map[string]int'
	assert map_python_type_to_v('datatypes.Set[int]', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'datatypes.Set[int]'
	assert map_python_type_to_v('List[int]', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == '[]int'
	assert map_python_type_to_v('val.args', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == '...Any'
	assert map_python_type_to_v('val.kwargs', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'map[string]Any'
}

fn test_map_union_types() {
	empty_fn := fn (a string, b string) string { return '' }
	empty_lit := fn (a []string) string { return '' }
	empty_tup := fn (a string) string { return '' }

	// Python 3.10+ unions
	assert map_python_type_to_v('int | str', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'int | string'
	assert map_python_type_to_v('int | None', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == '?int'
	assert map_python_type_to_v('str | int | None', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'string | int | NoneType'
	assert map_python_type_to_v('int | Any', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'Any'
	assert map_python_type_to_v('int | int', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'int'

	// typing.Union
	assert map_python_type_to_v('Union[int, str]', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'int | string'
	assert map_python_type_to_v('Union[int, None]', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == '?int'
	assert map_python_type_to_v('Union[int, Any]', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == 'Any'
	assert map_python_type_to_v('Optional[int]', '', true, map[string]string{}, empty_fn, empty_lit, empty_tup) == '?int'
}

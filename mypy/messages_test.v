module mypy

fn test_not_callable_reports_operator_error_code() {
	options := Options{}
	mut errors := new_errors(options)
	errors.set_file('test.py', '__main__')
	mut builder := MessageBuilder{
		errors:  &errors
		options: &options
	}
	context := Context{
		line:   12
		column: 3
	}

	typ := MypyTypeNode(AnyType{
		type_of_any: .special_form
	})
	builder.not_callable(typ, context)

	infos := errors.error_info_map['test.py'] or { panic('expected collected error') }
	assert infos.len == 1
	assert infos[0].message == 'Any not callable'
	code := infos[0].code or { panic('expected operator error code') }
	assert code == 'operator'
}

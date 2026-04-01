module classes

import ast
import base

fn noop_sum_type_registrar(_ string) string {
	return ''
}

fn noop_literal_registrar(_ []string) string {
	return ''
}

fn noop_tuple_registrar(_ string) string {
	return ''
}

fn (env &ClassVisitEnv) type_utils_context() base.TypeUtilsContext {
	return base.TypeUtilsContext{
		imported_symbols: env.state.imported_symbols
		scc_files:        env.state.scc_files.keys()
		used_builtins:    env.state.used_builtins
		warnings:         env.state.warnings
		include_all_symbols: env.state.include_all_symbols
		strict_exports:      env.state.strict_exports
	}
}

fn map_python_type(type_str string, struct_name string, is_return bool, mut env ClassVisitEnv) string {
	opts := base.TypeMapOptions{
		struct_name:        struct_name
		allow_union:        false
		register_sum_types: true
		is_return:          is_return
		generic_map:        env.state.current_class_generic_map
	}
	mut ctx := env.type_utils_context()
	
	// Check if this is a self-referential type (e.g., Packet -> Optional['Packet'])
	// We need to detect this BEFORE mapping, so we can return a pointer type
	is_optional := type_str.starts_with('?') || type_str.starts_with('Optional[') || type_str.contains('typing.Optional')
	mut clean_type := type_str.trim_left('?')
	if clean_type.starts_with('Optional[') && clean_type.ends_with(']') {
		clean_type = clean_type['Optional['.len..clean_type.len-1]
	}
	if clean_type.starts_with('typing.Optional[') && clean_type.ends_with(']') {
		clean_type = clean_type['typing.Optional['.len..clean_type.len-1]
	}
	// Check if clean_type refers to the current struct (self-reference)
	if clean_type == struct_name || clean_type.replace('_Impl', '') == struct_name || clean_type == struct_name.replace('_Impl', '') {
		// Self-referential type: use pointer type ?&StructName or &StructName
		real_name := struct_name.replace('_Impl', '')
		if is_optional {
			return '?&${real_name}'
		} else {
			return '&${real_name}'
		}
	}
	// Also check for the non-_Impl version
	if clean_type.len > 0 && clean_type[0].is_capital() && clean_type in env.state.defined_classes {
		if is_optional {
			// Check if this type is defined and is not the current struct
			if clean_type != struct_name && clean_type != struct_name.replace('_Impl', '') {
				// It's a different struct, might still need a pointer
				// But for now only handle self-references
			}
		}
	}
	
	return base.map_type(type_str, opts, mut ctx, fn [mut env] (name string) string {
		env.state.generated_sum_types[name] = ''
		return name
	}, noop_literal_registrar, noop_tuple_registrar)
}

fn guess_type(node ast.Expression, env &ClassVisitEnv) string {
	ctx := base.TypeGuessingContext{
		type_map:           env.analyzer.type_map
		location_map:       env.analyzer.location_map
		known_v_types:      env.state.known_v_types
		name_remap:         env.state.name_remap
		defined_classes:    env.state.defined_classes
		explicit_any_types: env.analyzer.explicit_any_types
		analyzer:           env.analyzer
	}
	return base.guess_type(node, ctx, true)
}

fn sanitize_name(name string, is_type bool) string {
	return base.sanitize_name(name, is_type, map[string]bool{}, '', map[string]bool{})
}

fn get_factory_name(struct_name string, env &ClassVisitEnv) string {
	return base.get_factory_name(struct_name, env.state.class_hierarchy)
}

fn get_generics_with_variance_str(env &ClassVisitEnv) string {
	mut v_generics := []string{}
	for py_name in env.state.current_class_generics {
		v_generics << env.state.current_class_generic_map[py_name] or { py_name }
	}
	return base.get_generics_with_variance_str(v_generics,
		env.state.current_class_generic_map, env.state.generic_variance, env.state.generic_defaults)
}

fn is_v_class_type(v_type string) bool {
	return v_type.len > 0 && v_type[0].is_capital() && v_type !in ['Any', 'LiteralString', 'Self']
}

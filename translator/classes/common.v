module classes

import ast
import base
import analyzer

fn noop_sum_type_registrar(_ string, _ string) string {
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
		imported_symbols:    env.state.imported_symbols
		scc_files:           env.state.scc_files
		used_builtins:       env.state.used_builtins
		warnings:            env.state.warnings
		include_all_symbols: env.state.include_all_symbols
		strict_exports:      env.state.strict_exports
	}
}

fn map_python_type(type_str string, struct_name string, is_return bool, mut env ClassVisitEnv, field_name string) string {
	mut real_type := type_str
	if struct_name == 'Task' && field_name == 'link' {
	}

	// If it's Any, try to look up a better type from analyzer/mypy
	if real_type == 'Any' && field_name.len > 0 {
		mut lookup_keys := ['${struct_name}.${field_name}']
		for key in lookup_keys {
			if t := env.analyzer.type_map[key] {
				if t != 'Any' {
					real_type = t
					break
				}
			}
			if env.analyzer.mypy_store.collected_types.len > 0 {
				if loc_map := env.analyzer.mypy_store.collected_types[key] {
					for _, typ in loc_map {
						t_v := analyzer.map_python_type_to_v(typ)
						real_type = t_v
						break
					}
					if real_type != 'Any' {
						break
					}
				}
			}
		}
	}

	opts := base.TypeMapOptions{
		struct_name:        struct_name
		allow_union:        false
		register_sum_types: true
		is_return:          is_return
		generic_map:        env.state.current_class_generic_map
	}
	mut ctx := env.type_utils_context()

	// Check if this is a self-referential type (e.g., Packet -> Optional['Packet'])
	is_optional := real_type.starts_with('?') || real_type.starts_with('Optional[')
		|| real_type.contains('typing.Optional') || real_type.contains('| None')
	mut clean_type := real_type.trim_left('?')
	// ... (rest of optional cleanup logic)
	if clean_type.starts_with('Optional[') && clean_type.ends_with(']') {
		clean_type = clean_type['Optional['.len..clean_type.len - 1]
	}
	if clean_type.starts_with('typing.Optional[') && clean_type.ends_with(']') {
		clean_type = clean_type['typing.Optional['.len..clean_type.len - 1]
	}
	if clean_type.ends_with(' | None') {
		clean_type = clean_type.all_before(' | None')
	}
	if clean_type.starts_with('None | ') {
		clean_type = clean_type.all_after('None | ')
	}
	clean_type = clean_type.trim('\'"')

	if clean_type == struct_name || clean_type.replace('_Impl', '') == struct_name
		|| clean_type == struct_name.replace('_Impl', '') {
		real_name := struct_name.replace('_Impl', '')
		if real_name in env.state.known_interfaces || real_name in env.state.class_to_impl {
			return if is_optional { '?${real_name}' } else { real_name }
		}
		return if is_optional { '?&${real_name}' } else { '&${real_name}' }
	}

	mapped := base.map_type(real_type, opts, mut ctx, fn [mut env] (name string, def string) string {
		if name.len > 0 {
			env.state.generated_sum_types[name] = def
			return name
		}
		return ''
	}, noop_literal_registrar, noop_tuple_registrar)

	// Prepend & for class types if missing
	mut final_v := mapped
	pure_v := final_v.trim_left('?&')

	if env.state.is_v_class_type(pure_v) && !pure_v.starts_with('&') && !pure_v.starts_with('[]')
		&& !pure_v.starts_with('datatypes.') {
		if pure_v in env.state.known_interfaces || pure_v in env.state.class_to_impl {
			return if final_v.starts_with('?') { '?' + pure_v } else { pure_v }
		}
		if final_v.starts_with('?') {
			final_v = '?&' + pure_v
		} else {
			final_v = '&' + pure_v
		}
	}
	if struct_name == 'Task' && field_name == 'link' {
	}
	pure_final := final_v.trim_left('?&')
	if pure_final in env.state.known_interfaces || pure_final in env.state.class_to_impl {
		return final_v.replace('&', '')
	}
	return final_v
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
	return base.get_generics_with_variance_str(v_generics, env.state.current_class_generic_map,
		env.state.generic_variance, env.state.generic_defaults)
}

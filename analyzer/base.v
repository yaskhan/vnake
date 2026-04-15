module analyzer

pub struct MutabilityInfo {
pub mut:
	is_reassigned bool
	is_final      bool
	is_mutated    bool
}

pub struct CallSignature {
pub mut:
	args                []string
	arg_names           []string
	defaults            map[string]string
	return_type         string
	is_class            bool
	has_init            bool
	has_vararg          bool
	has_kwarg           bool
	dataclass_metadata  map[string]string
	namedtuple_metadata map[string]string
	narrowed_type       ?string
	is_type_is          bool
}

pub struct TypeInferenceBase {
pub mut:
	type_map               map[string]string
	raw_type_map           map[string]string
	mutability_map         map[string]MutabilityInfo
	location_map           map[string]string
	call_signatures        map[string]CallSignature
	mixin_to_main          map[string][]string
	main_to_mixins         map[string][]string
	mixin_nodes            map[string]string
	static_methods         map[string][]string
	class_methods          map[string][]string
	is_abc                 map[string]bool
	class_hierarchy        map[string][]string
	scope_names            []string
	explicit_any_types     map[string]bool
	func_param_mutability  map[string][]int
	typed_dicts            map[string]bool
	literal_types          map[string]string // map[var_name]literal_value
	overloaded_signatures  map[string][]map[string]string
	type_vars              map[string]bool
	defined_classes_cache  map[string]map[string]bool
	empty_v_types_cache    map[string]string
	empty_name_remap_cache map[string]string
}

pub fn new_type_inference_base() TypeInferenceBase {
	return TypeInferenceBase{
		type_map:               map[string]string{}
		raw_type_map:           map[string]string{}
		mutability_map:         map[string]MutabilityInfo{}
		location_map:           map[string]string{}
		call_signatures:        map[string]CallSignature{}
		mixin_to_main:          map[string][]string{}
		main_to_mixins:         map[string][]string{}
		mixin_nodes:            map[string]string{}
		static_methods:         map[string][]string{}
		class_methods:          map[string][]string{}
		is_abc:                 map[string]bool{}
		class_hierarchy:        map[string][]string{}
		scope_names:            []string{}
		explicit_any_types:     map[string]bool{}
		func_param_mutability:  map[string][]int{}
		typed_dicts:            map[string]bool{}
		literal_types:          map[string]string{}
		overloaded_signatures:  map[string][]map[string]string{}
		type_vars:              map[string]bool{}
		defined_classes_cache:  map[string]map[string]bool{}
		empty_v_types_cache:    map[string]string{}
		empty_name_remap_cache: map[string]string{}
	}
}

pub fn (mut t TypeInferenceBase) push_scope(name string) {
	t.scope_names << name
}

pub fn (mut t TypeInferenceBase) pop_scope() {
	if t.scope_names.len > 0 {
		t.scope_names = t.scope_names[..t.scope_names.len - 1]
	}
}

pub fn (t &TypeInferenceBase) get_qualified_name(name string) string {
	if t.scope_names.len == 0 {
		return name
	}
	return t.scope_names.join('.') + '.' + name
}

pub fn (mut t TypeInferenceBase) set_type(name string, typ string) {
	t.type_map[name] = typ
}

pub fn (t &TypeInferenceBase) get_type(name string) string {
	if !name.contains('.') && t.scope_names.len > 0 {
		for i := t.scope_names.len - 1; i >= 0; i-- {
			qual := t.scope_names[..i + 1].join('.') + '.' + name
			if qual in t.type_map {
				res := t.type_map[qual]
				eprintln('DEBUG: analyzer.get_type scoped(${name}) ${qual} = ${res}')
				return res
			}
		}
	}

	if name in t.type_map {
		res := t.type_map[name]
		eprintln('DEBUG: analyzer.get_type ${name} = ${res}')
		return res
	}

	if name.contains('.') {
		cls := name.all_before_last('.')
		attr := name.all_after_last('.')
		bases := t.get_class_bases(cls)
		for b in bases {
			if b == 'object' {
				continue
			}
			mut res := t.get_type('${b}.${attr}')
			if res != 'Any' {
				return res
			}
			// Try CamelCase
			res = t.get_type('${b}.${to_camel_case(attr)}')
			if res != 'Any' {
				return res
			}
		}
	}
	return 'Any'
}

pub fn (t &TypeInferenceBase) get_call_signature(name string) ?CallSignature {
	if name in t.call_signatures {
		return t.call_signatures[name]
	}
	if name.contains('.') {
		cls := name.all_before_last('.')
		attr := name.all_after_last('.')
		bases := t.get_class_bases(cls)
		for b in bases {
			if b == 'object' {
				continue
			}
			if res := t.get_call_signature('${b}.${attr}') {
				return res
			}
			// Try CamelCase
			if res := t.get_call_signature('${b}.${to_camel_case(attr)}') {
				return res
			}
		}
	}
	return none
}

pub fn (t &TypeInferenceBase) has_type(name string) bool {
	return name in t.type_map
}

pub fn (mut t TypeInferenceBase) set_mutability(name string, info MutabilityInfo) {
	t.mutability_map[name] = info
}

pub fn (t &TypeInferenceBase) get_mutability(name string) MutabilityInfo {
	if !name.contains('.') && t.scope_names.len > 0 {
		for i := t.scope_names.len - 1; i >= 0; i-- {
			qual := t.scope_names[..i + 1].join('.') + '.' + name
			if qual in t.mutability_map {
				return t.mutability_map[qual]
			}
		}
	}

	if name in t.mutability_map {
		return t.mutability_map[name]
	}
	if name.contains('.') {
		cls := name.all_before_last('.')
		meth_arg := name.all_after_last('.')

		// 1. Look UP (inheritance)
		bases := t.get_class_bases(cls)
		for b in bases {
			if b == 'object' {
				continue
			}
			res := t.get_mutability('${b}.${meth_arg}')
			if res.is_mutated || res.is_reassigned {
				return res
			}
		}

		// 2. Look DOWN (interfaces -> implementations)
		// If current class is a base/interface, check if ANY child-impl has mut
		for potential_impl, parents in t.class_hierarchy {
			if cls in parents {
				res := t.get_mutability('${potential_impl}.${meth_arg}')
				if res.is_mutated || res.is_reassigned {
					return res
				}
			}
		}
	}
	return MutabilityInfo{}
}

pub fn (mut t TypeInferenceBase) add_class_to_hierarchy(class_name string, bases []string) {
	eprintln('DEBUG: TypeInferenceBase.add_class_to_hierarchy name=${class_name}')
	t.class_hierarchy[class_name] = bases
	t.defined_classes_cache[class_name] = map[string]bool{}
}

pub fn (t &TypeInferenceBase) get_class_bases(class_name string) []string {
	return t.class_hierarchy[class_name] or { []string{} }
}

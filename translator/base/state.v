module base

import ast

struct SourceTokenCarrier {
	token ast.Token
}

pub struct ExportConfigLike {
pub:
	include_all_symbols bool
}

pub struct TypeGuardInfo {
pub:
	narrowed_type string
	is_type_is    bool
}

// TranslatorState - translator state
@[heap]
pub struct TranslatorState {
pub mut:
	type_inference      voidptr
	compatibility       voidptr
	decorator_processor voidptr
	coroutine_handler   voidptr
	emitter             voidptr
	mapper              voidptr
	include_all_symbols bool
	strict_exports      bool

	output                       []string
	tail                         []string
	known_v_types                map[string]string
	indent_level                 int
	in_main                      bool
	current_class                string
	current_class_generics       []string
	current_class_generic_map    map[string]string
	current_class_bases          []string
	current_class_generic_bases  map[string]string
	current_class_body           []ast.Statement
	current_class_is_unittest    bool
	is_unittest_class            bool
	zip_counter                  int
	match_counter                int
	defined_classes              map[string]map[string]bool
	class_vars                   map[string][]map[string]string
	class_to_impl                map[string]string
	used_builtins                map[string]bool
	used_complex                 bool
	used_list_concat             bool
	used_delete_many             bool
	used_insert_many             bool
	used_dict_merge              bool
	used_string_format           bool
	dataclasses                  map[string][]string
	generated_sum_types          map[string]string
	generated_literal_enums      map[string]string
	generated_tuple_structs      map[string]string
	literal_enum_values          map[string]map[voidptr]string
	global_vars                  map[string]bool
	renamed_functions            map[string]string
	name_remap                   map[string]string
	walrus_assignments           []string
	imported_modules             map[string]string
	imported_symbols             map[string]string
	overloads                    map[string][]ast.FunctionDef
	single_dispatch_functions    map[string]map[string]string
	known_interfaces             map[string]bool
	class_hierarchy              map[string][]string
	main_to_mixins               map[string][]string
	type_guards                  map[string]TypeGuardInfo
	property_setters             map[string]map[string]bool
	function_names               map[string]bool
	overloaded_signatures        map[string][]map[string]string
	type_params_map              map[string][]string
	generic_variance             map[string]string
	abstract_methods             map[string][]string
	generic_defaults             map[string]string
	finally_stack                []voidptr
	loop_stack                   []map[string]voidptr
	generic_scopes               []map[string]string
	unique_id_counter            int
	vexc_depth                   int
	scope_stack                  []map[string]bool
	fstring_quote_stack          []string
	current_module_name          string
	current_file_name            string
	scc_files                    map[string]bool
	module_all                   []string
	defined_top_level_symbols    map[string]bool
	warnings                     []string
	pending_llm_call_comments    []string
	type_vars                    map[string]bool
	scope_names                  []string
	constrained_typevars         map[string]bool
	current_function_return_type string
	current_assignment_type      string
	current_assignment_lhs       string
	current_ann_raw              string
	in_pydantic_validator        bool
	in_init                      bool
	in_assignment_lhs            bool
	current_node                 voidptr
	readonly_fields              map[string]map[string]bool
	cond_optional_var_type       map[string]string
	typed_dicts                  map[string]bool
	class_hierarchy_initialized  bool
	cached_indents               []string
	is_full_module               bool
}

pub const cached_indents = [
	'',
	'    ',
	'        ',
	'            ',
	'                ',
	'                    ',
	'                        ',
	'                            ',
	'                                ',
	'                                    ',
	'                                        ',
	'                                            ',
	'                                                ',
	'                                                    ',
	'                                                        ',
	'                                                            ',
	'                                                                ',
	'                                                                    ',
	'                                                                        ',
	'                                                                            ',
	'                                                                                ',
]

// new_translator_state creates a new TranslatorState instance
pub fn new_translator_state() &TranslatorState {
	return &TranslatorState{
		type_inference:               unsafe { nil }
		compatibility:                unsafe { nil }
		decorator_processor:          unsafe { nil }
		coroutine_handler:            unsafe { nil }
		emitter:                      unsafe { nil }
		mapper:                       unsafe { nil }
		include_all_symbols:          false
		strict_exports:               false
		output:                       []string{}
		known_v_types:                map[string]string{}
		indent_level:                 0
		in_main:                      true
		current_class:                ''
		current_class_generics:       []string{}
		current_class_generic_map:    map[string]string{}
		current_class_bases:          []string{}
		current_class_generic_bases:  map[string]string{}
		current_class_body:           []ast.Statement{}
		current_class_is_unittest:    false
		is_unittest_class:            false
		zip_counter:                  0
		defined_classes:              map[string]map[string]bool{}
		class_vars:                   map[string][]map[string]string{}
		class_to_impl:                map[string]string{}
		used_builtins:                map[string]bool{}
		used_complex:                 false
		used_list_concat:             false
		used_delete_many:             false
		used_insert_many:             false
		used_dict_merge:              false
		used_string_format:           false
		dataclasses:                  map[string][]string{}
		generated_sum_types:          map[string]string{}
		generated_literal_enums:      map[string]string{}
		generated_tuple_structs:      map[string]string{}
		literal_enum_values:          map[string]map[voidptr]string{}
		global_vars:                  map[string]bool{}
		renamed_functions:            {
			'main': 'py_main'
		}
		name_remap:                   map[string]string{}
		walrus_assignments:           []string{}
		imported_modules:             map[string]string{}
		imported_symbols:             map[string]string{}
		single_dispatch_functions:    map[string]map[string]string{}
		abstract_methods:             map[string][]string{}
		known_interfaces:             map[string]bool{}
		class_hierarchy:              map[string][]string{}
		main_to_mixins:               map[string][]string{}
		property_setters:             map[string]map[string]bool{}
		function_names:               map[string]bool{}
		overloaded_signatures:        map[string][]map[string]string{}
		type_params_map:              map[string][]string{}
		generic_variance:             map[string]string{}
		generic_defaults:             map[string]string{}
		finally_stack:                []voidptr{}
		loop_stack:                   []map[string]voidptr{}
		generic_scopes:               []map[string]string{}
		unique_id_counter:            0
		vexc_depth:                   0
		scope_stack:                  []map[string]bool{}
		fstring_quote_stack:          []string{}
		current_module_name:          'main'
		current_file_name:            ''
		scc_files:                    map[string]bool{}
		module_all:                   []string{}
		defined_top_level_symbols:    map[string]bool{}
		warnings:                     []string{}
		pending_llm_call_comments:    []string{}
		type_vars:                    map[string]bool{}
		scope_names:                  []string{}
		constrained_typevars:         map[string]bool{}
		current_function_return_type: ''
		current_assignment_type:      ''
		in_pydantic_validator:        false
		in_init:                      false
		in_assignment_lhs:            false
		current_node:                 unsafe { nil }
		readonly_fields:              map[string]map[string]bool{}
		cond_optional_var_type:       map[string]string{}
		typed_dicts:                  map[string]bool{}
		class_hierarchy_initialized:  false
		cached_indents:               cached_indents.clone()
		is_full_module:               false
	}
}

// indent returns indentation string.
// This is optimized to use precomputed indentation strings for common levels.
pub fn (s &TranslatorState) indent() string {
	if s.indent_level >= 0 && s.indent_level < s.cached_indents.len {
		return s.cached_indents[s.indent_level]
	}
	return '    '.repeat(s.indent_level)
}

// create_temp creates a temporary variable
pub fn (mut s TranslatorState) create_temp() string {
	s.unique_id_counter++
	return 'py_aug_tmp_${s.unique_id_counter}'
}

// create_temp_with_prefix creates a temporary variable with given prefix
pub fn (mut s TranslatorState) create_temp_with_prefix(prefix string) string {
	s.unique_id_counter++
	return '${prefix}${s.unique_id_counter}'
}

// get_source_info returns source code information
pub fn (s &TranslatorState) get_source_info(t ast.Token) string {
	if t.line > 0 {
		return '${s.current_file_name}:${t.line}:${t.column}'
	}
	return '${s.current_file_name}:?:?'
}

// update_class_hierarchy updates class hierarchy
pub fn (mut s TranslatorState) update_class_hierarchy() {
	if s.class_hierarchy_initialized {
		return
	}

	for class_name in s.defined_classes.keys() {
		if class_name !in s.class_hierarchy {
			s.class_hierarchy[class_name] = []string{}
		}
	}

	for class_name, bases in s.class_hierarchy {
		mut uniq := map[string]bool{}
		mut normalized := []string{}
		for b in bases {
			if b.len == 0 || b in uniq {
				continue
			}
			uniq[b] = true
			normalized << b
		}
		s.class_hierarchy[class_name] = normalized
	}

	s.class_hierarchy_initialized = true
}

// is_top_level_symbol checks if name is a top-level symbol
pub fn (s &TranslatorState) is_top_level_symbol(name string) bool {
	if s.current_class.len > 0 {
		return false
	}
	for scope in s.scope_stack {
		if name in scope {
			return false
		}
	}
	return true
}

// is_compile_time_evaluable checks if expression is compile-time evaluable
pub fn is_compile_time_evaluable(node ast.Expression) bool {
	if node is ast.Constant {
		return true
	}
	if node is ast.UnaryOp {
		return is_compile_time_evaluable(node.operand)
	}
	if node is ast.List {
		if node.elements.len == 0 { return true }
	}
	return false
}

// is_exported checks if symbol should be public
pub fn (s &TranslatorState) is_exported(name string) bool {
	if s.include_all_symbols {
		return true
	}
	if name.starts_with('_') {
		return false
	}
	if s.module_all.len > 0 {
		return name in s.module_all
	}
	return false
}

// collect_assigned_vars collects names of all assigned variables
pub fn (s &TranslatorState) collect_assigned_nodes(nodes []voidptr) map[string]bool {
	mut assigned := map[string]bool{}
	for node in nodes {
		if node == unsafe { nil } {
			continue
		}
		h := unsafe { &SourceTokenCarrier(node) }
		if h.token.typ == .identifier && h.token.value.len > 0 {
			assigned[h.token.value] = true
		}
	}
	return assigned
}





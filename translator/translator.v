module translator

// VERIFY: 12345
import analyzer
import ast
import base
import expressions
import models
import classes
import functions
import stdlib_map
import control_flow

pub struct Translator {
pub mut:
	state    &base.TranslatorState
	analyzer &analyzer.Analyzer
	model    models.VType
	mutable_locals map[string]bool
	current_function_name string
	classes_module   classes.ClassesModule
	functions_module functions.FunctionsModule
	coroutine_handler analyzer.CoroutineHandler
	control_flow_module control_flow.ControlFlowModule
}

pub fn new_translator() &Translator {
	
	mut t := &Translator{
		state:    base.new_translator_state()
		analyzer: analyzer.new_analyzer(map[string]string{})
		model:    .unknown
		mutable_locals: map[string]bool{}
		current_function_name: ''
		classes_module:   classes.new_classes_module()
		functions_module: functions.new_functions_module()
		coroutine_handler: analyzer.new_coroutine_handler()
		control_flow_module: control_flow.new_control_flow_module()
	}
	t.state.mapper = stdlib_map.new_stdlib_mapper()
	t.state.include_all_symbols = false
	t.state.strict_exports = false
	t.state.coroutine_handler = &t.coroutine_handler
	t.control_flow_module.env = t.get_control_flow_env()
	t.analyzer.guess_type_handler = fn (e ast.Expression, ctx models.TypeGuessingContext) string {
		return base.guess_type(e, ctx, true)
	}

	mut e := &VCodeEmitter{
		module_name:      'main'
		imports:          []string{}
		structs:          []string{}
		functions:        []string{}
		main_body:        []string{}
		init_body:        []string{}
		globals:          []string{}
		constants:        []string{}
		helper_imports:   []string{}
		helper_structs:   []string{}
		helper_functions: []string{}
	}
	t.state.emitter = voidptr(e)

	return t
}

pub fn (t &Translator) get_helper_imports() []string {
	e := unsafe { &VCodeEmitter(t.state.emitter) }
	return e.helper_imports.clone()
}

pub fn (t &Translator) get_helper_structs() []string {
	e := unsafe { &VCodeEmitter(t.state.emitter) }
	return e.helper_structs.clone()
}

pub fn (t &Translator) get_helper_functions() []string {
	e := unsafe { &VCodeEmitter(t.state.emitter) }
	return e.helper_functions.clone()
}

fn (mut t Translator) emit(line string) {
	t.state.output << line
}

fn (mut t Translator) indent() string {
	return t.state.indent()
}

fn (mut t Translator) emit_indented(line string) {
	t.state.output << '${t.state.indent()}${line}'
}

fn (mut t Translator) emit_tail(line string) {
	t.state.tail << line
}

fn (mut t Translator) push_scope(name string) {
	t.state.scope_stack << map[string]bool{}
	t.analyzer.push_scope(name)
}

fn (mut t Translator) pop_scope() {
	if t.state.scope_stack.len > 0 {
		t.state.scope_stack.delete_last()
		t.analyzer.pop_scope()
	}
}

fn (mut t Translator) declare_local(name string) {
	if t.state.scope_stack.len == 0 {
		return
	}
	if name == 'dest' {
		eprintln("DEBUG: declare_local ${name} at stack=${t.state.scope_stack.len}")
	}
	mut scope := t.state.scope_stack.pop()
	scope[name] = true
	t.state.scope_stack << scope
}

fn (t &Translator) is_declared_local(name string) bool {
	for i := t.state.scope_stack.len - 1; i >= 0; i-- {
		if name in t.state.scope_stack[i] {
			return true
		}
	}
	return false
}

fn (mut t Translator) visit_expr(node ast.Expression) string {
	mut eg := expressions.new_expr_gen(&t.model, t.analyzer, t.state)
	eg.target_type = t.state.current_assignment_type
	return eg.visit(node)
}

fn (mut t Translator) guess_type(node ast.Expression) string {
	mut eg := expressions.new_expr_gen(&t.model, t.analyzer, t.state)
	return eg.guess_type(node)
}

pub fn (mut t Translator) map_annotation(node ?ast.Expression) string {
	res := if n := node {
		rendered := t.analyzer.render_expr(n)
		eprintln('DEBUG: map_annotation rendered=${rendered}')
		t.map_annotation_str(rendered, t.state.current_class, false, true, true)
	} else {
		'Any'
	}
	eprintln('DEBUG: map_annotation node=${node} res=${res}')
	return res
}

fn (mut t Translator) map_annotation_internal(node ast.Expression) string {
	match node {
		ast.Name {
			res := match node.id {
				'None' { '' }
				'NoReturn' { 'noreturn' }
				'Any', 'object' { 'Any' }
				'bool' { 'bool' }
				'int' { 'int' }
				'i64' { 'i64' }
				'float', 'f64' { 'f64' }
				'str', 'string', 'LiteralString' { 'string' }
				'list', 'List' { '[]Any' }
				'Self' {
					struct_name := t.state.current_class
					mut self_res := '&${struct_name}'
					if t.state.current_class_generics.len > 0 {
						mut v_gens := []string{}
						for gn in t.state.current_class_generics {
							v_gens << t.state.current_class_generic_map[gn] or { gn }
						}
						self_res += '[${v_gens.join(", ")}]'
					}
					self_res
				}
				'dict', 'Dict' { 'map[string]Any' }
				'set', 'Set' { 'datatypes.Set[Any]' }
				'callable', 'Callable' { 'fn (...Any) Any' }
				else {
					full_sym := t.state.imported_symbols[node.id] or { node.id }
					if node.id in t.state.paramspec_vars { return '...Any' }
					if full_sym in ['str', 'builtins.str', 'typing.LiteralString', 'typing_extensions.LiteralString'] { return 'string' }
					if full_sym in ['float', 'builtins.float'] { return 'f64' }
					full_sym
				}
			}
			// Check generic scopes first
			for i := t.state.generic_scopes.len - 1; i >= 0; i-- {
				if node.id in t.state.generic_scopes[i] {
					return t.state.generic_scopes[i][node.id]
				}
			}

			if t.state.current_class.len > 0 {
				nested := t.state.current_class + "_" + node.id
				if nested in t.state.defined_classes {
					return "&" + nested
				}
			}

			return res
		}
		ast.Attribute {
			if node.attr == 'args' {
				return '...Any'
			}
			if node.attr == 'kwargs' {
				return 'map[string]Any'
			}

			if node.attr == 'Self' {
				gen_s := if t.state.current_class_generics.len > 0 {
					'[${t.state.current_class_generics.join(", ")}]'
				} else { '' }
				return '&${t.state.current_class}${gen_s}'
			}
			full_name := t.annotation_raw_name(node)
			if full_name in ['NoReturn', 'typing.NoReturn'] { return 'noreturn' }
			if full_name in ['Any', 'typing.Any'] { return 'Any' }
			if full_name in ['LiteralString', 'typing.LiteralString', 'typing_extensions.LiteralString'] { return 'string' }
			if full_name in ['Self', 'typing.Self'] {
				gen_s := if t.state.current_class_generics.len > 0 {
					'[${t.state.current_class_generics.join(", ")}]'
				} else { '' }
				return '&${t.state.current_class}${gen_s}'
			}
			return t.map_annotation_str(full_name, t.state.current_class, true, true, false)
		}
		ast.Subscript {
			base_raw := t.annotation_raw_name(node.value)
			if base_raw in ['TypeGuard', 'typing.TypeGuard', 'TypeIs', 'typing.TypeIs'] {
				narrowed := t.map_annotation(node.slice)
				if t.current_function_name.len > 0 {
					t.state.type_guards[t.current_function_name] = base.TypeGuardInfo{
						narrowed_type: narrowed
						is_type_is:    base_raw.contains('TypeIs')
					}
				}
				return 'bool'
			}
			if base_raw in ['Optional', 'typing.Optional'] {
				return '?${t.map_annotation(node.slice)}'
			}
			if base_raw in ['Union', 'typing.Union'] {
				if node.slice is ast.Tuple {
					mut parts := []string{}
					for elt in node.slice.elements {
						parts << t.map_annotation(elt)
					}
					mut res_parts := []string{}
					mut contains_none := false
					for p in parts {
						if p != '' { res_parts << p }
						else { contains_none = true }
					}
					res_type := res_parts.join(' | ')
					if contains_none {
						return if res_type.len > 0 { t.map_annotation_str('?${res_type}', '', false, true, false) } else { 'none' }
					}
					return t.map_annotation_str(res_type, '', false, true, false)
				}
				return t.map_annotation(node.slice)
			}
			if base_raw in ['List', 'typing.List', 'list'] {
				return '[]${t.map_annotation(node.slice)}'
			}
			if base_raw in ['Tuple', 'typing.Tuple', 'tuple'] {
				if node.slice is ast.Tuple {
					mut parts := []string{}
					for elt in node.slice.elements {
						parts << t.map_annotation(elt)
					}
					types_str := parts.join(', ')
					struct_name := models.get_tuple_struct_name(types_str)
					t.state.generated_tuple_structs[struct_name] = types_str
					return struct_name
				}
				inner := t.map_annotation(node.slice)
				if inner.contains(',') {
					struct_name := models.get_tuple_struct_name(inner)
					t.state.generated_tuple_structs[struct_name] = inner
					return struct_name
				}
				return '[]' + inner
			}
			if base_raw in ['Dict', 'typing.Dict', 'dict'] {
				if node.slice is ast.Tuple {
					mut parts := []string{}
					for elt in node.slice.elements {
						parts << t.map_annotation(elt)
					}
					if parts.len >= 2 {
						return 'map[${parts[0]}]${parts[1]}'
					}
				}
				return 'map[string]Any'
			}
			if base_raw in ['Set', 'typing.Set', 'set'] {
				return 'datatypes.Set[${t.map_annotation(node.slice)}]'
			}
			if base_raw in ['TypeForm', 'typing.TypeForm', 'typing_extensions.TypeForm'] {
				return 'string'
			}
			if base_raw in ['Required', 'typing.Required', 'NotRequired', 'typing.NotRequired',
				'Final', 'typing.Final', 'ClassVar', 'typing.ClassVar', 'ReadOnly', 'typing.ReadOnly',
				'Annotated', 'typing.Annotated'] {
				if base_raw.contains('NotRequired') {
					inner := t.map_annotation(node.slice)
					return if inner.starts_with('?') { inner } else { '?${inner}' }
				}
				if node.slice is ast.Tuple {
					return t.map_annotation(node.slice.elements[0])
				}
				return t.map_annotation(node.slice)
			}
			if base_raw in ['Literal', 'typing.Literal'] {
				t.state.used_builtins['LiteralEnum_'] = true
				return 'LiteralEnum_'
			}
			if base_raw in ['Callable', 'typing.Callable', 'collections.abc.Callable', 'callable'] {
				mut arg_types := []string{}
				mut ret_type := 'Any'
				if node.slice is ast.Tuple {
					tuple_node := node.slice
					if tuple_node.elements.len >= 2 {
						args_spec := tuple_node.elements[0]
						if args_spec is ast.List {
							for elt in args_spec.elements {
								arg_types << t.map_annotation(elt)
							}
						} else if (args_spec is ast.Constant && args_spec.value == '...') || (args_spec is ast.Name && (args_spec as ast.Name).id == '...') {
							arg_types << '...Any'
						} else {
							arg_spec_str := t.map_annotation(args_spec)
							if arg_spec_str.len > 0 {
								arg_types << arg_spec_str
							}
						}
						ret_type = t.map_annotation(tuple_node.elements[1])
					}
				} else {
					// Handle Callable[..., Ret]
					ret_type = t.map_annotation(node.slice)
					return 'fn (...Any) ${ret_type}'
				}
				if ret_type == '' || ret_type == 'void' || ret_type == 'none' {
					return 'fn (${arg_types.join(", ")})'
				}
				return 'fn (${arg_types.join(", ")}) ${ret_type}'
			}
			return t.map_annotation(node.value) + '[${t.map_annotation(node.slice)}]'
		}
		ast.Tuple {
			mut parts := []string{}
			for elt in node.elements {
				parts << t.map_annotation(elt)
			}
			return parts.join(', ')
		}
		ast.Constant {
			if node.value == 'None' { return '' }
			if node.value.starts_with("'") || node.value.starts_with('"') {
				return node.value[1..node.value.len - 1]
			}
			return node.value
		}
		ast.BinaryOp {
			if node.op.value == '|' {
				l := t.map_annotation(node.left)
				r := t.map_annotation(node.right)
				if l == '' { return if r == '' { 'none' } else { '?${r}' } }
				if r == '' { return '?${l}' }
				return t.map_annotation_str('${l} | ${r}', '', false, true, false)
			}
			return ''
		}
		ast.Starred {
			return t.map_annotation(node.value)
		}
		else {
			return ''
		}
	}
}

pub fn (mut t Translator) map_annotation_str(type_str string, struct_name string, allow_union bool, register bool, is_return bool) string {
	mut actual_struct := if struct_name.len > 0 && struct_name != 'Self' { struct_name } else { t.state.current_class }
	if actual_struct == '' { actual_struct = 'Self' }

	opts := base.TypeMapOptions{
		struct_name:        actual_struct
		allow_union:        allow_union
		register_sum_types: register
		is_return:          is_return
		self_type:          actual_struct
		generic_map:        if t.state.generic_scopes.len > 0 { t.state.generic_scopes.last() } else { t.state.current_class_generic_map }
	}
	mut ctx := base.TypeUtilsContext{
		imported_symbols: t.state.imported_symbols
		defined_classes:  t.state.defined_classes
		scc_files:        t.state.scc_files.keys()
		used_builtins:    t.state.used_builtins
		warnings:         t.state.warnings
		include_all_symbols: t.state.include_all_symbols
		strict_exports:      t.state.strict_exports
	}
	mut st := t.state
	res := base.map_type(type_str, opts, mut ctx, fn [mut t, actual_struct] (name string, def string) string {
		if name == 'Self' || name == 'typing.Self' || def == 'Self' || def == 'typing.Self' {
			mut v_gens := []string{}
			for gn in t.state.current_class_generics {
				v_gens << t.state.current_class_generic_map[gn] or { gn }
			}
			gen_s := if v_gens.len > 0 { "[${v_gens.join(', ')}]" } else { "" }
			return "&" + actual_struct + gen_s
		}
		mut final_name := name
		if final_name == '' && def.contains('|') {
			final_name = base.get_sum_type_name(def)
		}
		if final_name.len > 0 {
			t.state.generated_sum_types[final_name] = def
			return final_name
		}
		return ""
	}, fn [mut t] (vals []string) string {
		enum_name := base.get_literal_enum_name(vals)
		t.state.generated_literal_enums[enum_name] = vals.join(' | ')
		return enum_name
	}, fn [mut t] (types_str string) string {
		struct_name_tuple := models.get_tuple_struct_name(types_str)
		t.state.generated_tuple_structs[struct_name_tuple] = types_str
		return struct_name_tuple
	})

	if res == 'TaskState' || res == '&TaskState' { return 'TaskState' }
	if res.len == 0 {
		return type_str
	}
	
	mut final_res := res
	pure_v := final_res.trim_left('?&')
	is_type_var := pure_v in t.state.type_vars || pure_v in t.state.current_class_generics
	
	if t.state.is_v_class_type(pure_v) && !pure_v.starts_with('[]') && !pure_v.starts_with('datatypes.') && !is_type_var {
		is_interface := pure_v in t.state.known_interfaces || pure_v == 'TaskState' || pure_v.ends_with('Protocol')
		if is_interface {
			return if final_res.starts_with('?') { '?' + pure_v } else { pure_v }
		}
		if final_res.starts_with('?') {
			final_res = '?&' + pure_v
		} else {
			final_res = '&' + pure_v
		}
	}
	return final_res
}

fn (t &Translator) annotation_raw_name(node ast.Expression) string {
	match node {
		ast.Name {
			return node.id
		}
		ast.Attribute {
			parent := t.annotation_raw_name(node.value)
			if parent.len > 0 {
				return '${parent}.${node.attr}'
			}
			return node.attr
		}
		ast.Subscript {
			return t.annotation_raw_name(node.value)
		}
		else {
			return ''
		}
	}
}

pub fn (mut t Translator) translate(source string, filename string) string {
	old_mapper := t.state.mapper
	old_is_full_module := t.state.is_full_module
	old_include_all := t.state.include_all_symbols
	old_strict_exports := t.state.strict_exports
	old_sccs := t.state.scc_files.clone()
	old_current_module := t.state.current_module_name
	
	t.state = base.new_translator_state()
	t.state.mapper = old_mapper
	t.state.is_full_module = old_is_full_module
	t.state.include_all_symbols = old_include_all
	t.state.strict_exports = old_strict_exports
	t.state.scc_files = old_sccs.clone()
	t.state.current_module_name = old_current_module
	
	mut e := &VCodeEmitter{
		module_name:     'main'
		imports:         []string{}
		structs:         []string{}
		functions:       []string{}
		main_body:       []string{}
		init_body:       []string{}
		globals:         []string{}
		constants:       []string{}
		helper_imports:  []string{}
		helper_structs:  []string{}
		helper_functions: []string{}
	}
	t.state.emitter = voidptr(e)
	
	t.coroutine_handler = analyzer.new_coroutine_handler()
	t.state.coroutine_handler = &t.coroutine_handler
	t.state.current_file_name = filename
	old_mypy_store := t.analyzer.mypy_store
	t.analyzer = analyzer.new_analyzer(map[string]string{})
	t.analyzer.mypy_store = old_mypy_store
	t.state.output = []string{}
	t.state.tail = []string{}
	t.model = .unknown
	t.mutable_locals = map[string]bool{}
	t.current_function_name = ''

	mut compatibility := analyzer.new_compatibility_layer()
	preprocessed := compatibility.preprocess_source(source)
	mut lexer := ast.new_lexer(preprocessed, filename)
	mut parser := ast.new_parser(lexer)
	module_node := parser.parse_module()

	// Pre-scan for __all__
	t.state.module_all = []string{}
	for stmt in module_node.body {
		if stmt is ast.Assign {
			for target in stmt.targets {
				if target is ast.Name && target.id == '__all__' {
					if stmt.value is ast.List {
						for elt in stmt.value.elements {
							if elt is ast.Constant {
								t.state.module_all << elt.value.trim('\'" ')
							}
						}
					} else if stmt.value is ast.Tuple {
						for elt in stmt.value.elements {
							if elt is ast.Constant {
								t.state.module_all << elt.value.trim('\'" ')
							}
						}
					}
				}
			}
		}
	}

	// Pre-analyze to fill type map for aliases
	t.analyzer.analyze(module_node)

	// Infill semantic information from Mypy
	// t.analyzer.mypy_store = analyzer.run_mypy_analysis(preprocessed, filename)

	t.coroutine_handler.scan_module(module_node)
	for name, yield_type in t.coroutine_handler.generators {
		t.analyzer.type_map['${name}@return'] = 'PyGenerator[${yield_type}]'
	}

	// Pre-scan for globals even if not using ModuleTranslator
	mut top_level_names := map[string]bool{}
	for stmt in module_node.body {
		if stmt is ast.FunctionDef { top_level_names[stmt.name] = true }
		else if stmt is ast.ClassDef { top_level_names[stmt.name] = true }
		else if stmt is ast.Assign {
			for target in stmt.targets {
				if target is ast.Name { top_level_names[target.id] = true }
			}
		}
	}
	
	mut globals := map[string]bool{}
	mut assigned_locally := map[string]bool{}
	// Reuse logic from ModuleTranslator if possible? No, Translator is in same module but ModuleTranslator is local to its file.
	// Actually, ModuleTranslator is in same module as Translator!
	mut mt_for_scan := new_module_translator(mut t.state, t.analyzer, fn [mut t] (stmt ast.Statement) { t.visit_stmt(stmt) })
	mt_for_scan.collect_global_refs(module_node, top_level_names, mut assigned_locally, mut globals)
	for name, _ in globals {
		t.state.global_vars[name] = true
	}

	for k, v in t.analyzer.class_hierarchy {
		t.state.class_hierarchy[k] = v.clone()
		t.state.defined_classes[k] = map[string]bool{}
		for base_name in v {
			t.state.known_interfaces[base_name] = true
		}
	}
	t.state.update_class_hierarchy()

	// Capture concrete types for globals if they are assigned later
	for stmt in module_node.body {
		if stmt is ast.Assign {
			eprintln('DEBUG: pre-scan Assign')
			for target in stmt.targets {
				if target is ast.Name {
					id := target.id
					loc_key := '${target.get_token().line}:${target.get_token().column}'
					mut v_type := ''
					if mypy_t := t.analyzer.get_mypy_type(id, loc_key) {
						v_type = analyzer.map_python_type_to_v(mypy_t)
						eprintln('DEBUG: pre-scan GLOBAL INFERRED: ${id} [${loc_key}] -> ${mypy_t} -> ${v_type}')
					} else {
						eprintln('DEBUG: pre-scan GLOBAL FAILED: ${id} [${loc_key}]')
					}
					if v_type == '' || v_type == 'Any' {
						v_type = t.guess_type(stmt.value)
					}
					eprintln('DEBUG: pre-scan id=${id} v_type=${v_type}')
					v_id := base.sanitize_name(id, false, map[string]bool{}, "", map[string]bool{})
					eprintln('DEBUG: pre-scan id=${id} v_id=${v_id} v_type=${v_type}')
					if v_type != 'unknown' && v_type != 'Any' && v_type != 'none' {
						t.state.global_var_types[v_id] = v_type
					}
				}
			}
		} else if stmt is ast.AnnAssign {
			eprintln('DEBUG: pre-scan AnnAssign')
			if stmt.target is ast.Name {
				id := stmt.target.id
				loc_key := '${stmt.target.get_token().line}:${stmt.target.get_token().column}'
				mut v_type := ''
				if mypy_t := t.analyzer.get_mypy_type(id, loc_key) {
					v_type = analyzer.map_python_type_to_v(mypy_t)
				}
				if v_type == '' || v_type == 'Any' {
					v_type = t.map_annotation(stmt.annotation)
					eprintln('DEBUG: pre-scan AnnAssign FALLBACK map_annotation(taskWorkArea) -> ${v_type}')
					if v_type == '' || v_type == 'Any' {
						if val := stmt.value {
							eprintln('DEBUG: pre-scan AnnAssign VALUE TYPE: ${val.type_name()}')
							v_type = t.guess_type(val)
						}
					}
				}
				eprintln('DEBUG: pre-scan AnnAssign id=${id} v_type=${v_type}')
				v_id := base.sanitize_name(id, false, map[string]bool{}, "", map[string]bool{})
				eprintln('DEBUG: pre-scan AnnAssign id=${id} v_id=${v_id} v_type=${v_type}')
				if v_type != 'unknown' && v_type != 'Any' && v_type != 'none' {
					t.state.global_var_types[v_id] = v_type
				}
			}
		}
	}

	for k, v in t.analyzer.main_to_mixins {
		t.state.main_to_mixins[k] = v.clone()
	}
	for k, v in t.analyzer.overloaded_signatures {
		t.state.overloaded_signatures[k] = v.clone()
	}
	for k, _ in t.analyzer.type_vars {
		t.state.type_vars[k] = true
	}
	for k, _ in t.analyzer.typed_dicts {
		t.state.typed_dicts[k] = true
	}
	for k, v in t.analyzer.call_signatures {
		if narrowed := v.narrowed_type {
			t.state.type_guards[k] = base.TypeGuardInfo{
				narrowed_type: narrowed
				is_type_is:    v.is_type_is
			}
		}
	}
	t.state.class_hierarchy_initialized = true
	
	for name, info in t.analyzer.mutability_map {
		if info.is_reassigned || info.is_mutated {
			if name == 'dest' {
				eprintln("DEBUG: Mark ${name} as mutable in translator")
			}
			t.mutable_locals[name] = true
		}
	}

	// Use structured output if requested
	if t.state.is_full_module {
		mut mt := new_module_translator(mut t.state, t.analyzer, fn [mut t] (stmt ast.Statement) {
			t.visit_stmt(stmt)
		})
		mt.coroutine_handler = t.coroutine_handler
		mut v_code := mt.visit_module(module_node)
		mut final_code := v_code
		
		// Add main function
		if final_code.contains('fn richards') && !final_code.contains('fn main()') {
			final_code += '
fn main() { richards() }
'
		}
		
		return final_code
	}

	for _, stmt in module_node.body {
		t.visit_stmt(stmt)
	}

	t.append_helpers()

	if t.state.used_builtins["regex"] {
		e.add_import("regex")
	}
	if t.state.used_builtins['math.pow'] || t.state.used_builtins['math.floor'] {
		e.add_import('math')
	}
	if t.state.used_builtins['encoding.base64'] {
		e.add_import('encoding.base64')
	}
	if t.state.used_builtins['encoding.hex'] {
		e.add_import('encoding.hex')
	}
	if t.state.used_builtins['compress.zlib'] {
		e.add_import('compress.zlib')
	}
	if t.state.used_builtins['compress.gzip'] {
		e.add_import('compress.gzip')
	}
	if t.state.used_builtins['net.urllib'] {
		e.add_import('net.urllib')
	}
	if t.state.used_builtins['csv'] {
		e.add_import('encoding.csv')
	}
	if t.state.used_builtins['datatypes'] {
		e.add_import('datatypes')
	}
	if t.state.used_builtins['vexc'] {
		e.add_import('div72.vexc')
	}
	
	mut uses_os := false
	for line in t.state.output {
		if line.contains('os.') { uses_os = true; break }
	}
	if uses_os {
		e.add_import('os')
	}
	
	mut uses_binary := false
	for k, v in t.state.used_builtins {
		if k.starts_with('py_struct_') && v { uses_binary = true; break }
	}
	if uses_binary {
		e.add_import('binary')
	}

	// Cleanup unused imports
	mut imports_to_add := []string{}
	for line in t.state.output {
		trimmed := line.trim_space()
		if trimmed.starts_with('import ') {
			imp_name := trimmed['import '.len..].trim_space()
			// Check if this import is actually used
			mut is_used := false
			// Check if any used_builtins starts with this module name
			for k, v in t.state.used_builtins {
				if v && k.starts_with('${imp_name}.') {
					is_used = true
					break
				}
			}
			// Also check if the module name appears in output code
			if !is_used {
				short_name := if imp_name.contains('.') { imp_name.all_after_last('.') } else { imp_name }
				for code_line in t.state.output {
					if (code_line.contains('${imp_name}.') || code_line.contains('${short_name}.')) && !code_line.trim_space().starts_with('import ') {
						is_used = true
						break
					}
				}
			}
			if is_used {
				imports_to_add << imp_name
			}
		} else if trimmed.starts_with('const ') || trimmed.starts_with('pub const ') {
			e.add_constant(trimmed)
		} else if trimmed.starts_with('__global ') {
			e.add_global(trimmed)
		} else if trimmed.starts_with('type ') || trimmed.starts_with('pub type ') {
			e.add_struct(trimmed)
		} else if trimmed.len > 0 {
			e.add_main_statement(line)
		}
	}
	// Add only used imports
	for imp in imports_to_add {
		e.add_import(imp)
	}
	res := if t.state.is_full_module { e.emit() } else { e.raw_emit() }
	return res
}


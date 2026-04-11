// I, Cline, am working on this file. Started: 2026-03-22 20:31
// semanal.v вЂ” The semantic analyzer
// Translated from mypy/semanal.py
// Note: this is a very large file (~3000 lines), translated main structures and key functions

module mypy

// Scope constants
pub const scope_global = 0
pub const scope_class = 1
pub const scope_func = 2
pub const scope_comprehension = 3
pub const scope_annotation = 4

// FUTURE_IMPORTS вЂ” mapping of future imports to flags
pub const future_imports = {
	'__future__.nested_scopes':    'nested_scopes'
	'__future__.generators':       'generators'
	'__future__.division':         'division'
	'__future__.absolute_import':  'absolute_import'
	'__future__.with_statement':   'with_statement'
	'__future__.print_function':   'print_function'
	'__future__.unicode_literals': 'unicode_literals'
	'__future__.barry_as_FLUFL':   'barry_as_FLUFL'
	'__future__.generator_stop':   'generator_stop'
	'__future__.annotations':      'annotations'
}

// CORE_BUILTIN_CLASSES вЂ” basic builtins classes
pub const core_builtin_classes = ['object', 'type', 'list', 'dict', 'str', 'int', 'float', 'bool',
	'bytes', 'tuple', 'set']
// Marker used in missing_names to signal unresolved bindings in the current pass.
pub const incomplete_ref_marker = '<incomplete_ref>'

// SemanticAnalyzer вЂ” mypy semantic analyzer
@[heap]
pub struct SemanticAnalyzer {
pub mut:
	modules                              map[string]&MypyFile
	globals                              SymbolTable
	global_decls                         []map[string]bool
	nonlocal_decls                       []map[string]bool
	locals                               []?SymbolTable
	scope_stack                          []int
	block_depth                          []int
	cur_type                             ?&TypeInfo
	type_stack                           []?&TypeInfo
	tvar_scope                           TypeVarLikeScope
	options                              Options
	function_stack                       []FuncItem
	progress                             bool
	deferred                             bool
	incomplete                           bool
	final_iteration                      bool
	missing_names                        []map[string]bool
	loop_depth                           []int
	cur_mod_id                           string
	is_stub_file                         bool
	is_typeshed_stub_file                bool
	imports                              map[string]bool
	errors                               Errors
	plugin                               Plugin
	statement                            ?Statement
	cur_mod_node                         ?&MypyFile
	msg                                  MessageBuilder
	scope                                Scope
	recurse_into_function_bodies         bool
	incomplete_type_stack                []bool
	allow_unbound_tvars                  bool
	basic_type_applications              bool
	current_overload_item                ?int
	inside_except_star_block             bool
	return_stmt_inside_except_star_block bool
	all_exports                          []string
	saved_locals                         map[string]SymbolTable
	incomplete_namespaces                map[string]bool
	deferral_debug_context               [][]string
	transitive_submodule_imports         map[string]map[string]bool
	patches                              []PatchEntry
	future_import_flags                  map[string]bool
}

// new_semantic_analyzer creates a new SemanticAnalyzer
pub fn new_semantic_analyzer(modules map[string]&MypyFile, errors Errors, plugin Plugin, options Options) &SemanticAnalyzer {
	mut sa := &SemanticAnalyzer{
		modules:                              modules
		globals:                              SymbolTable{}
		global_decls:                         [map[string]bool{}]
		nonlocal_decls:                       [map[string]bool{}]
		locals:                               [?SymbolTable(none)]
		scope_stack:                          [scope_global]
		block_depth:                          [0]
		cur_type:                             none
		type_stack:                           []?&TypeInfo{}
		tvar_scope:                           TypeVarLikeScope{}
		options:                              options
		function_stack:                       []FuncItem{}
		progress:                             false
		deferred:                             false
		incomplete:                           false
		final_iteration:                      false
		missing_names:                        [map[string]bool{}]
		loop_depth:                           [0]
		cur_mod_id:                           ''
		is_stub_file:                         false
		is_typeshed_stub_file:                false
		imports:                              map[string]bool{}
		errors:                               errors
		plugin:                               plugin
		statement:                            none
		cur_mod_node:                         none
		msg:                                  MessageBuilder{
			modules: map[string]&MypyFile{}
		}
		scope:                                Scope{}
		recurse_into_function_bodies:         true
		incomplete_type_stack:                []bool{}
		allow_unbound_tvars:                  false
		basic_type_applications:              false
		current_overload_item:                none
		inside_except_star_block:             false
		return_stmt_inside_except_star_block: false
		all_exports:                          []string{}
		saved_locals:                         map[string]SymbolTable{}
		incomplete_namespaces:                map[string]bool{}
		deferral_debug_context:               [][]string{}
		transitive_submodule_imports:         map[string]map[string]bool{}
		patches:                              []PatchEntry{}
		future_import_flags:                  map[string]bool{}
	}
	sa.msg.errors = &sa.errors
	sa.msg.options = &sa.options
	return sa
}

// type returns the current TypeInfo
pub fn (sa SemanticAnalyzer) type() ?&TypeInfo {
	return sa.cur_type
}

// is_stub_file checks if the file is a stub
pub fn (sa SemanticAnalyzer) is_stub_file() bool {
	return sa.is_stub_file
}

// is_typeshed_stub_file checks if the file is a stub from typeshed
pub fn (sa SemanticAnalyzer) is_typeshed_stub_file() bool {
	return sa.is_typeshed_stub_file
}

// final_iteration checks if this is the final iteration
pub fn (sa SemanticAnalyzer) final_iteration() bool {
	return sa.final_iteration
}

// prepare_file prepares a file for analysis
pub fn (mut sa SemanticAnalyzer) prepare_file(mut file_node MypyFile) {
	sa.future_import_flags = file_node.future_import_flags.clone()
	if 'builtins' in sa.modules {
		file_node.names.symbols['__builtins__'] = SymbolTableNode{
			kind: gdef
			node: SymbolNodeRef(sa.modules['builtins'])
		}
	}
	if file_node.fullname == 'builtins' {
		sa.prepare_builtins_namespace(mut file_node)
	}
}

// prepare_builtins_namespace adds special definitions to builtins
fn (sa SemanticAnalyzer) prepare_builtins_namespace(mut file MypyFile) {
	mut names := file.names
	for name in core_builtin_classes {
		cdef := ClassDef{
			name: name
			defs: Block{
				body: []
			}
		}
		mut info := new_type_info(mut names, &cdef, 'builtins')
		info.fullname = 'builtins.${name}'
		names.symbols[name] = SymbolTableNode{
			kind: gdef
			node: SymbolNodeRef(*info)
		}
	}

	special_names := ['None', 'reveal_type', 'reveal_locals', 'True', 'False', '__debug__']

	for name in special_names {
		mut v := Var{
			name:     name
			fullname: 'builtins.${name}'
			type_:    MypyTypeNode(Instance{
				type_name: 'bool'
				args:      []MypyTypeNode{}
			})
		}
		if name == 'None' {
			v.type_ = MypyTypeNode(Instance{
				type_name: 'NoneType'
				args:      []MypyTypeNode{}
			})
		}

		names.symbols[name] = SymbolTableNode{
			kind: gdef
			node: SymbolNodeRef(v)
		}
	}
}

// visit_mypy_file handles &MypyFile
pub fn (mut sa SemanticAnalyzer) visit_mypy_file(mut file_node MypyFile) !AnyNode {
	// Ensure builtins are prepared
	if 'builtins' !in sa.modules && file_node.fullname != 'builtins' {
		mut builtins_file := &MypyFile{
			fullname: 'builtins'
			path:     'builtins.py'
		}
		sa.prepare_builtins_namespace(mut builtins_file)
		sa.modules['builtins'] = builtins_file
	}
	sa.prepare_file(mut file_node)

	sa.cur_mod_node = file_node
	sa.cur_mod_id = file_node.fullname

	sa.globals = file_node.names

	for mut defn in file_node.defs {
		defn.accept(mut sa)!
	}
	file_node.future_import_flags = sa.future_import_flags.clone()
	return ''
}

// visit_func_def handles function definition
pub fn (mut sa SemanticAnalyzer) visit_func_def(mut defn FuncDef) !AnyNode {
	sa.statement = Statement(defn)

	for mut arg in defn.arguments {
		if mut init := arg.initializer {
			init.accept(mut sa)!
		}
	}

	defn.is_conditional = sa.block_depth.last() > 0
	defn.fullname = sa.qualified_name(defn.name)

	if !sa.recurse_into_functions() || sa.function_stack.len > 0 {
		if !defn.is_decorated && !defn.is_overload {
			sa.add_function_to_symbol_table(mut defn)
		}
	}

	if !sa.recurse_into_functions() && !defn.def_or_infer_vars {
		return ''
	}

	sa.function_stack << defn
	sa.analyze_func_def(mut defn)!
	sa.function_stack.pop()
	return ''
}

// analyze_func_def analyzes function definition
fn (mut sa SemanticAnalyzer) analyze_func_def(mut defn FuncDef) !AnyNode {
	if sa.push_type_args(defn.type_params, defn.base) == none {
		sa.defer(defn.base.get_context(), false)
		return ''
	}

	sa.function_stack << defn

	mut has_self_type := false
	if defn.type_ != none {
		if defn.type_ is CallableType {
			sa.update_function_type_variables(defn.type_ as CallableType, defn)
		}
	}
	_ = has_self_type

	sa.function_stack.pop()

	if sa.is_class_scope() {
		defn.info = sa.cur_type
	}

	// Function signature analysis
	if sig := defn.type_ {
		if analyzed_sig := sa.anal_type(sig, none, false, false, false, true, true, none,
			none)
		{
			defn.type_ = analyzed_sig
		}
	}

	sa.analyze_function_body(mut defn)!
	sa.pop_type_args(defn.type_params)
	return ''
}

// visit_class_def handles class definition
pub fn (mut sa SemanticAnalyzer) visit_class_def(mut defn ClassDef) !AnyNode {
	sa.statement = Statement(defn)
	sa.analyze_class(mut defn)!
	return ''
}

// analyze_class analyzes class definition
fn (mut sa SemanticAnalyzer) analyze_class(mut defn ClassDef) !AnyNode {
	fullname := sa.qualified_name(defn.name)

	if defn.info == none && !sa.is_core_builtin_class(defn) {
		placeholder := PlaceholderNode{
			fullname:         fullname
			node:             SymbolNodeRef(*defn)
			becomes_typeinfo: true
		}
		sa.add_symbol(defn.name, placeholder, defn.get_context(), true, false, true)
	}

	// Full class analysis implementation
	sa.prepare_class_def(mut defn)!
	sa.setup_type_vars(defn, [])
	sa.analyze_base_classes(mut defn)!
	if mut info := defn.info {
		calculate_mro(mut *info) or {
			sa.fail('Cannot determine consistent Method Resolution Order (MRO) for class "' +
				defn.name + '"', defn.get_context(), false, false, none)
		}
		check_protocol_status(info, mut sa.errors)
	}

	sa.enter_class(defn.info or { return '' })
	defn.defs.accept(mut sa)!
	sa.leave_class()
	return ''
}

// visit_import handles import
pub fn (mut sa SemanticAnalyzer) visit_import(mut i Import) !AnyNode {
	sa.statement = Statement(i)
	for item in i.ids {
		id := item.name
		as_id := item.alias
		use_implicit_reexport := !sa.is_stub_file() && sa.options.implicit_reexport
		base_id := if alias := as_id {
			_ = alias
			id
		} else {
			id.split('.')[0]
		}
		imported_id := if alias := as_id { alias } else { base_id }
		module_public := use_implicit_reexport || if alias := as_id { id == alias } else { false }
		_ = base_id
		_ = imported_id

		if base_id in sa.modules {
			node := sa.modules[base_id]
			kind := if sa.is_func_scope() {
				ldef
			} else if sa.cur_type != none {
				mdef
			} else {
				gdef
			}
			symbol := SymbolTableNode{
				kind:          kind
				node:          SymbolNodeRef(node)
				module_public: module_public
				module_hidden: !module_public
			}
			sa.add_imported_symbol(imported_id, symbol, i, module_public, !module_public)
		} else {
			sa.add_unknown_imported_symbol(imported_id, i.base, base_id, module_public,
				!module_public)
		}
	}
	return ''
}

// visit_import_from handles from ... import
pub fn (mut sa SemanticAnalyzer) visit_import_from(mut imp ImportFrom) !AnyNode {
	sa.statement = Statement(imp)
	mod_id := sa.correct_relative_import(imp)
	mod := sa.modules[mod_id] or { return '' }

	for item in imp.names {
		id := item.name
		as_id := item.alias
		fullname := '${mod_id}.${id}'
		sa.set_future_import_flags(fullname)

		mut node := ?SymbolTableNode(none)
		if id in mod.names.symbols {
			node = mod.names.symbols[id]
		}

		imported_id := if as_val := as_id { as_val } else { id }
		_ = imported_id
		use_implicit_reexport := !sa.is_stub_file() && sa.options.implicit_reexport
		module_public := use_implicit_reexport || (as_id != none && id == as_id or { '' })

		if it_node := node {
			sa.add_imported_symbol(imported_id, it_node, imp.base, module_public, !module_public)
		} else {
			sa.report_missing_module_attribute(mod_id, id, imported_id, imp.base)
		}
	}
	return ''
}

// visit_assignment_stmt handles assignment
pub fn (mut sa SemanticAnalyzer) visit_assignment_stmt(mut s AssignmentStmt) !AnyNode {
	sa.statement = Statement(s)

	if sa.analyze_identity_global_assignment(s) {
		return ''
	}

	if sa.analyze_rvalue(mut s)! {
		return ''
	}

	if sa.check_for_special_forms(mut s) {
		return ''
	}

	s.is_final_def = sa.unwrap_final(s)
	for mut lv_expr in s.lvalues {
		if mut lv := lv_expr.as_lvalue() {
			sa.analyze_lvalue(mut lv, false, false)!
		}
	}
	sa.store_final_status(mut s)
	sa.check_classvar(mut s)
	if sa.process_type_annotation(mut s) {
		return ''
	}
	return ''
}

// visit_if_stmt handles if
pub fn (mut sa SemanticAnalyzer) visit_if_stmt(mut s IfStmt) !AnyNode {
	sa.statement = Statement(s)
	infer_reachability_of_if_statement(mut s, sa.options)
	for i in 0 .. s.expr.len {
		s.expr[i].accept(mut sa)!
		sa.visit_block(mut s.body[i])!
	}
	sa.visit_block_maybe(s.else_body)!
	return ''
}

// visit_block handles block
pub fn (mut sa SemanticAnalyzer) visit_block(mut b Block) !AnyNode {
	if b.is_unreachable {
		return ''
	}
	sa.block_depth[sa.block_depth.len - 1]++
	for mut s in b.body {
		sa.accept(mut s)
	}
	sa.block_depth[sa.block_depth.len - 1]--
	return ''
}

// visit_block_maybe handles optional block
pub fn (mut sa SemanticAnalyzer) visit_block_maybe(b ?Block) !AnyNode {
	if mut it_b := b {
		sa.visit_block(mut it_b)!
	}
	return ''
}

// visit_while_stmt handles while
pub fn (mut sa SemanticAnalyzer) visit_while_stmt(mut s WhileStmt) !AnyNode {
	sa.statement = Statement(s)
	s.expr.accept(mut sa)!
	sa.loop_depth[sa.loop_depth.len - 1]++
	sa.visit_block(mut s.body)!
	sa.visit_block_maybe(s.else_body)!
	sa.loop_depth[sa.loop_depth.len - 1]--
	return ''
}

// visit_for_stmt handles for
pub fn (mut sa SemanticAnalyzer) visit_for_stmt(mut s ForStmt) !AnyNode {
	if s.is_async {
		if !sa.is_async_context() {
			sa.msg.fail("'async for' outside async function", s.get_context(), false,
				false, none)
		}
	}
	sa.statement = Statement(s)
	s.expr.accept(mut sa)!
	if mut lval := s.index.as_lvalue() {
		sa.analyze_lvalue(mut lval, false, s.index_type != none)!
	}
	sa.loop_depth[sa.loop_depth.len - 1]++
	sa.visit_block(mut s.body)!
	sa.loop_depth[sa.loop_depth.len - 1]--
	sa.visit_block_maybe(s.else_body)!
	return ''
}

// visit_return_stmt handles return
pub fn (mut sa SemanticAnalyzer) visit_return_stmt(mut s ReturnStmt) !AnyNode {
	if !sa.is_func_scope() {
		sa.fail('"return" outside function', s.get_context(), false, false, none)
	}
	if s.expr != none {
		s.expr.accept(mut sa)!
	}
	return ''
}

// visit_break_stmt handles break
pub fn (mut sa SemanticAnalyzer) visit_break_stmt(mut s BreakStmt) !AnyNode {
	sa.statement = Statement(s)
	if sa.loop_depth.last() == 0 {
		sa.fail('"break" outside loop', s.get_context(), true, true, none)
	}
	return ''
}

// visit_continue_stmt handles continue
pub fn (mut sa SemanticAnalyzer) visit_continue_stmt(mut s ContinueStmt) !AnyNode {
	sa.statement = Statement(s)
	if sa.loop_depth.last() == 0 {
		sa.fail('"continue" outside loop', s.get_context(), true, true, none)
	}
	return ''
}

// visit_try_stmt handles try
pub fn (mut sa SemanticAnalyzer) visit_try_stmt(mut s TryStmt) !AnyNode {
	sa.statement = Statement(s)
	s.body.accept(mut sa)!
	for mut handler in s.handlers {
		sa.visit_block(mut handler)!
	}
	if mut else_body := s.else_body {
		sa.visit_block(mut else_body)!
	}
	if mut finally_body := s.finally_body {
		sa.visit_block(mut finally_body)!
	}
	return ''
}

// visit_decorator handles decorator
pub fn (mut sa SemanticAnalyzer) visit_decorator(mut dec Decorator) !AnyNode {
	sa.statement = Statement(dec)
	// dec.decorators is initialized already
	dec.func.is_conditional = sa.block_depth.last() > 0

	if !dec.is_overload {
		sa.add_symbol(dec.func.name, SymbolNodeRef(*dec), dec.get_context(), true, false,
			true)
	}

	dec.func.fullname = sa.qualified_name(dec.func.name)
	dec.var_.fullname = sa.qualified_name(dec.func.name)

	for mut d in dec.decorators {
		d.accept(mut sa)!

		d_str := d.str()
		if d_str == 'staticmethod' {
			dec.func.is_static = true
			dec.var_.is_staticmethod = true
		} else if d_str == 'classmethod' {
			dec.func.is_class = true
		} else if d_str == 'property' {
			dec.func.is_property = true
			dec.var_.is_property = true
		} else if d_str in ['abstractmethod', 'abc.abstractmethod'] {
			dec.func.abstract_status = 1
			dec.var_.is_abstract_var = true
		} else if d_str in ['final', 'typing.final'] {
			dec.func.is_final = true
			dec.var_.is_final = true
		}
	}

	return ''
}

// visit_expression_stmt handles Expression statement
pub fn (mut sa SemanticAnalyzer) visit_expression_stmt(mut s ExpressionStmt) !AnyNode {
	sa.statement = Statement(s)
	s.expr.accept(mut sa)!
	return ''
}

// visit_name_expr handles name
pub fn (mut sa SemanticAnalyzer) visit_name_expr(mut expr NameExpr) !AnyNode {
	n := sa.lookup(expr.name, expr.base)
	if node := n {
		sa.bind_ref_expr(mut expr, node)
	} else {
		sa.msg.fail('Name "${expr.name}" is not defined', expr.get_context(), false, false,
			none)
	}
	return ''
}

// visit_member_expr handles member access
pub fn (mut sa SemanticAnalyzer) visit_member_expr(mut expr MemberExpr) !AnyNode {
	expr.expr.accept(mut sa)!

	// Handle qualified names (e.g. module.name)
	if expr.expr is NameExpr {
		node := expr.expr as NameExpr
		if sym := sa.lookup(node.name, node.base) {
			if msym_node := sym.node {
				if msym_node is MypyFile {
					if msym := msym_node.names.symbols[expr.name] {
						sa.bind_ref_expr(mut expr, msym)
					}
				}
			}
		}
	}

	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_call_expr(mut expr CallExpr) !AnyNode {
	expr.callee.accept(mut sa)!
	for mut a in expr.args {
		a.accept(mut sa)!
	}
	return ''
}

// visit_int_expr handles int literal
pub fn (mut sa SemanticAnalyzer) visit_int_expr(mut expr IntExpr) !AnyNode {
	// Do nothing
	return ''
}

// visit_str_expr handles string literal
pub fn (mut sa SemanticAnalyzer) visit_str_expr(mut expr StrExpr) !AnyNode {
	// Do nothing
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_var(mut o Var) !AnyNode {
	if mut t := o.type_ {
		if analyzed_t := sa.anal_type(t, none, false, false, false, true, true, none,
			none)
		{
			o.type_ = analyzed_t
		}
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_type_alias(mut o TypeAlias) !AnyNode {
	if analyzed_target := sa.anal_type(o.target, none, false, false, false, true, true,
		none, none)
	{
		o.target = analyzed_target
	}
	return ''
}

// visit_placeholder_node handles placeholder node
pub fn (mut sa SemanticAnalyzer) visit_placeholder_node(mut o PlaceholderNode) !AnyNode {
	// Unresolved placeholders must trigger another semantic-analysis pass.
	sa.defer(o.get_context(), false)
	// Record the incomplete state so callers can detect unfinished binding.
	sa.record_incomplete_ref()
	return ''
}

// visit_type_info handles type info
pub fn (mut sa SemanticAnalyzer) visit_type_info(mut o TypeInfo) !AnyNode {
	sa.enter_class(&o)
	defer {
		sa.leave_class()
	}

	if mut defn := o.defn {
		defn.defs.accept(mut sa)!
		return ''
	}

	for _, mut sym in o.names.symbols {
		if mut node := sym.node {
			// Class symbol tables may point back to the owning TypeInfo, so skip
			// the self-edge to avoid infinite recursion during traversal.
			if node is TypeInfo && node.fullname == o.fullname {
				continue
			}
			node.accept(mut sa)!
		}
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_bytes_expr(mut o BytesExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_float_expr(mut o FloatExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_complex_expr(mut o ComplexExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_ellipsis(mut o EllipsisExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_star_expr(mut o StarExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_yield_from_expr(mut o YieldFromExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_yield_expr(mut o YieldExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_op_expr(mut o OpExpr) !AnyNode {
	o.left.accept(mut sa)!
	o.right.accept(mut sa)!
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_comparison_expr(mut o ComparisonExpr) !AnyNode {
	for mut operand in o.operands {
		operand.accept(mut sa)!
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_cast_expr(mut o CastExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_assert_type_expr(mut o AssertTypeExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_reveal_expr(mut o RevealExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_super_expr(mut o SuperExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_unary_expr(mut o UnaryExpr) !AnyNode {
	o.expr.accept(mut sa)!
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_assignment_expr(mut o AssignmentExpr) !AnyNode {
	o.value.accept(mut sa)!
	if mut lval := o.target.as_lvalue() {
		sa.analyze_lvalue(mut lval, false, false)!
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_index_expr(mut o IndexExpr) !AnyNode {
	o.base_.accept(mut sa)!
	o.index.accept(mut sa)!
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_type_application(mut o TypeApplication) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_lambda_expr(mut o LambdaExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_list_comprehension(mut o ListComprehension) !AnyNode {
	o.generator.accept(mut sa)!
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_set_comprehension(mut o SetComprehension) !AnyNode {
	o.generator.accept(mut sa)!
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_dictionary_comprehension(mut o DictionaryComprehension) !AnyNode {
	o.key.accept(mut sa)!
	o.value.accept(mut sa)!
	for i in 0 .. o.indices.len {
		if mut lval := o.indices[i].as_lvalue() {
			sa.analyze_lvalue(mut lval, false, false)!
		}
		o.sequences[i].accept(mut sa)!
		for mut cond in o.condlists[i] {
			cond.accept(mut sa)!
		}
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_generator_expr(mut o GeneratorExpr) !AnyNode {
	o.left_expr.accept(mut sa)!
	for i in 0 .. o.indices.len {
		if mut lval := o.indices[i].as_lvalue() {
			sa.analyze_lvalue(mut lval, false, false)!
		}
		o.sequences[i].accept(mut sa)!
		for mut cond in o.condlists[i] {
			cond.accept(mut sa)!
		}
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_list_expr(mut o ListExpr) !AnyNode {
	for mut item in o.items {
		item.accept(mut sa)!
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_dict_expr(mut o DictExpr) !AnyNode {
	for i in 0 .. o.items.len {
		if mut k := o.items[i].key {
			k.accept(mut sa)!
		}
		o.items[i].value.accept(mut sa)!
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_template_str_expr(mut o TemplateStrExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_tuple_expr(mut o TupleExpr) !AnyNode {
	for mut item in o.items {
		item.accept(mut sa)!
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_set_expr(mut o SetExpr) !AnyNode {
	for mut item in o.items {
		item.accept(mut sa)!
	}
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_slice_expr(mut o SliceExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_conditional_expr(mut o ConditionalExpr) !AnyNode {
	o.cond.accept(mut sa)!
	o.if_expr.accept(mut sa)!
	o.else_expr.accept(mut sa)!
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_type_var_expr(mut o TypeVarExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_paramspec_expr(mut o ParamSpecExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_type_var_tuple_expr(mut o TypeVarTupleExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_type_alias_expr(mut o TypeAliasExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_namedtuple_expr(mut o NamedTupleExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_enum_call_expr(mut o EnumCallExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_typeddict_expr(mut o TypedDictExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_newtype_expr(mut o NewTypeExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_promote_expr(mut o PromoteExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_temp_node(mut o TempNode) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_await_expr(mut o AwaitExpr) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_with_stmt(mut o WithStmt) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_del_stmt(mut o DelStmt) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_overloaded_func_def(mut o OverloadedFuncDef) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_global_decl(mut o GlobalDecl) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_nonlocal_decl(mut o NonlocalDecl) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_import_all(mut o ImportAll) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_operator_assignment_stmt(mut o OperatorAssignmentStmt) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_assert_stmt(mut o AssertStmt) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_raise_stmt(mut o RaiseStmt) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_type_alias_stmt(mut o TypeAliasStmt) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_match_stmt(mut o MatchStmt) !AnyNode {
	return ''
}

// Patterns
pub fn (mut sa SemanticAnalyzer) visit_as_pattern(mut o AsPattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_or_pattern(mut o OrPattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_value_pattern(mut o ValuePattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_singleton_pattern(mut o SingletonPattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_sequence_pattern(mut o SequencePattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_starred_pattern(mut o StarredPattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_mapping_pattern(mut o MappingPattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_class_pattern(mut o ClassPattern) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_argument(mut o Argument) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_type_param(mut o TypeParam) !AnyNode {
	return ''
}

pub fn (mut sa SemanticAnalyzer) visit_lvalue(mut o Lvalue) !AnyNode {
	match mut o {
		ListExpr { sa.visit_list_expr(mut o)! }
		MemberExpr { sa.visit_member_expr(mut o)! }
		NameExpr { sa.visit_name_expr(mut o)! }
		StarExpr { sa.visit_star_expr(mut o)! }
		TupleExpr { sa.visit_tuple_expr(mut o)! }
		IndexExpr { sa.visit_index_expr(mut o)! }
	}
	return ''
}

// visit_pass_stmt handles pass
pub fn (sa SemanticAnalyzer) visit_pass_stmt(mut s PassStmt) !AnyNode {
	// Do nothing
	return ''
}

// accept accepts a node
pub fn (mut sa SemanticAnalyzer) accept(mut node Node) {
	node.accept(mut sa) or {}
}

// lookup looks up a name
pub fn (mut sa SemanticAnalyzer) lookup(name string, context NodeBase) ?SymbolTableNode {
	// Search in local scopes
	for i := sa.locals.len - 1; i >= 0; i-- {
		if locals := sa.locals[i] {
			if name in locals.symbols {
				return locals.symbols[name]
			}
		}
	}

	// Search in global scope
	if name in sa.globals.symbols {
		return sa.globals.symbols[name]
	}

	// Search in builtins
	if 'builtins' in sa.modules {
		builtins := sa.modules['builtins'] or { return none }
		if name in builtins.names.symbols {
			return builtins.names.symbols[name]
		}
	}

	return none
}

// lookup_qualified looks up a qualified name
pub fn (mut sa SemanticAnalyzer) lookup_qualified(name string, ctx Context, suppress_errors bool) ?&SymbolTableNode {
	if !name.contains('.') {
		return sa.lookup_ptr(name, ctx)
	}

	parts := name.split('.')
	if parts.len < 2 {
		return none
	}

	// Lookup first part
	first := parts[0]
	mut current := sa.lookup_ptr(first, ctx) or { return none }

	// Navigate through remaining parts
	for i in 1 .. parts.len {
		part := parts[i]
		current_node := current.node or { return none }
		if current_node is TypeInfo {
			if part in current_node.names.symbols {
				current = unsafe { &current_node.names.symbols[part] }
			} else {
				return none
			}
		} else if current_node is MypyFile {
			if part in current_node.names.symbols {
				current = unsafe { &current_node.names.symbols[part] }
			} else {
				return none
			}
		} else {
			return none
		}
	}

	return current
}

// lookup_ptr is a version of lookup that returns a pointer
fn (mut sa SemanticAnalyzer) lookup_ptr(name string, context Context) ?&SymbolTableNode {
	// Search in local scopes
	for i := sa.locals.len - 1; i >= 0; i-- {
		if mut locals := sa.locals[i] {
			if name in locals.symbols {
				return unsafe { &locals.symbols[name] }
			}
		}
	}

	// Search in global scope
	if name in sa.globals.symbols {
		return unsafe { &sa.globals.symbols[name] }
	}

	// Search in builtins
	if 'builtins' in sa.modules {
		builtins := sa.modules['builtins'] or { return none }
		if name in builtins.names.symbols {
			return unsafe { &builtins.names.symbols[name] }
		}
	}

	return none
}

fn (mut sa SemanticAnalyzer) bind_ref_expr(mut expr RefExpr, sym SymbolTableNode) {
	match mut expr {
		NameExpr {
			expr.kind = sym.kind
			if node := sym.node {
				expr.node = node.as_mypy_node()
			}
		}
		MemberExpr {
			expr.kind = sym.kind
			if node := sym.node {
				expr.node = node.as_mypy_node()
			}
		}
	}
}

// analyze_lvalue analyzes lvalue
pub fn (mut sa SemanticAnalyzer) analyze_lvalue(mut lval Lvalue, nested bool, explicit_type bool) !AnyNode {
	match mut lval {
		NameExpr {
			sym := sa.lookup(lval.name, lval.base)
			if sym == none {
				// Define new variable
				mut v := Var{
					name:     lval.name
					fullname: sa.qualified_name(lval.name)
				}
				sa.add_symbol(lval.name, SymbolNodeRef(v), lval.get_context(), true, false,
					true)
				sa.bind_ref_expr(mut lval, sa.lookup(lval.name, lval.base) or { SymbolTableNode{} })
			} else if node := sym {
				sa.bind_ref_expr(mut lval, node)
			}
		}
		MemberExpr {
			lval.accept(mut sa)!
		}
		TupleExpr {
			for mut item in lval.items {
				if mut l := item.as_lvalue() {
					sa.analyze_lvalue(mut l, true, explicit_type)!
				}
			}
		}
		ListExpr {
			for mut item in lval.items {
				if mut l := item.as_lvalue() {
					sa.analyze_lvalue(mut l, true, explicit_type)!
				}
			}
		}
		StarExpr {
			if mut l := lval.expr.as_lvalue() {
				sa.analyze_lvalue(mut l, true, explicit_type)!
			}
		}
		IndexExpr {
			lval.accept(mut sa)!
		}
	}
	return ''
}

fn (sa SemanticAnalyzer) flatten_lvalues(lvalues []Expression) []Expression {
	mut res := []Expression{}
	for lval in lvalues {
		match lval {
			TupleExpr {
				res << sa.flatten_lvalues(lval.items)
			}
			ListExpr {
				res << sa.flatten_lvalues(lval.items)
			}
			else {
				res << lval
			}
		}
	}
	return res
}

fn annotation_head_name(typ MypyTypeNode) string {
	if typ is UnboundType {
		parts := typ.name.split('.')
		return parts.last()
	}
	return ''
}

fn unwrap_assignment_annotation(typ MypyTypeNode) MypyTypeNode {
	mut current := typ
	for {
		snapshot := current
		if snapshot is UnboundType {
			ub := snapshot as UnboundType
			if ub.args.len > 0 && annotation_head_name(snapshot) in ['Final', 'ClassVar'] {
				current = ub.args[0]
				continue
			}
		}
		break
	}
	return current
}

fn (sa SemanticAnalyzer) is_classvar_type(typ MypyTypeNode) bool {
	return typ is UnboundType && annotation_head_name(typ) == 'ClassVar'
}

fn (mut sa SemanticAnalyzer) store_declared_type(mut lvalue Expression, typ MypyTypeNode) {
	match mut lvalue {
		NameExpr {
			if mut sym := sa.lookup_ptr(lvalue.name, lvalue.get_context()) {
				if mut node := sym.node {
					if mut node is Var {
						node.type_ = typ
						node.is_inferred = false
						sym.node = SymbolNodeRef(node)
						lvalue.node = MypyNode(node)
					}
				}
			}
		}
		MemberExpr {
			if mut node := lvalue.node {
				if mut node is Var {
					node.type_ = typ
					node.is_inferred = false
				}
			}
		}
		StarExpr {
			sa.store_declared_type(mut lvalue.expr, typ)
		}
		else {}
	}
}

fn assignment_has_explicit_value(rvalue Expression) bool {
	// Annotation-only declarations use TempNode as a placeholder for a
	// missing RHS. Some producers construct TempNode{} without setting
	// no_rhs = true, so relying on that flag misclassifies declarations as
	// having an explicit value.
	return rvalue !is TempNode
}

fn (mut sa SemanticAnalyzer) store_final_status(mut s AssignmentStmt) {
	if !s.is_final_def || s.lvalues.len != 1 {
		return
	}
	folded_value := constant_fold_expr(s.rvalue, sa.cur_mod_id)
	has_explicit_value := assignment_has_explicit_value(s.rvalue)
	lvalue := s.lvalues[0]
	match lvalue {
		NameExpr {
			if mut sym := sa.lookup_ptr(lvalue.name, lvalue.get_context()) {
				if mut node := sym.node {
					if mut node is Var {
						node.is_final = true
						if folded_value != none {
							node.final_value = s.rvalue
						}
						if has_explicit_value {
							node.has_explicit_value = true
						}
						sym.node = SymbolNodeRef(node)
					}
				}
			}
		}
		MemberExpr {
			if mut node := lvalue.node {
				if mut node is Var {
					node.is_final = true
					if folded_value != none {
						node.final_value = s.rvalue
					}
					if has_explicit_value {
						node.has_explicit_value = true
					}
				}
			}
		}
		else {}
	}
}

fn (mut sa SemanticAnalyzer) check_classvar(mut s AssignmentStmt) {
	if s.lvalues.len != 1 {
		return
	}
	ann := s.type_annotation or { return }
	if !sa.is_classvar_type(ann) {
		return
	}
	if sa.is_class_scope() && s.lvalues[0] is NameExpr {
		lvalue := s.lvalues[0] as NameExpr
		if mut sym := sa.lookup_ptr(lvalue.name, lvalue.get_context()) {
			if mut node := sym.node {
				if mut node is Var {
					node.is_classvar = true
					sym.node = SymbolNodeRef(node)
				}
			}
		}
	}
	if ann is UnboundType && ann.args.len == 0 {
		if s.rvalue is TempNode && (s.rvalue as TempNode).no_rhs {
			return
		}
		// Bare ClassVar with an initializer behaves like an inferred assignment, so we drop the
		// outer wrapper and let downstream logic use the assigned value without a phantom wrapper type.
		s.type_annotation = none
	}
}

fn (mut sa SemanticAnalyzer) process_type_annotation(mut s AssignmentStmt) bool {
	ann := s.type_annotation or { return false }
	allow_tuple_literal := s.lvalues.len > 0 && s.lvalues.last() is TupleExpr
	normalized := unwrap_assignment_annotation(ann)
	analyzed := sa.anal_type(normalized, none, allow_tuple_literal, false, false, true, true,
		none, none) or {
		sa.defer(s.get_context(), false)
		return true
	}
	if has_placeholder(analyzed) {
		sa.defer(s.get_context(), false)
		return true
	}
	s.type_annotation = analyzed
	for mut lvalue in sa.flatten_lvalues(s.lvalues) {
		sa.store_declared_type(mut lvalue, analyzed)
	}
	return false
}

// names_modified_by_assignment returns names modified in assignment
fn (mut sa SemanticAnalyzer) names_modified_by_assignment(s AssignmentStmt) []NameExpr {
	mut result := []NameExpr{}
	for lval_expr in s.lvalues {
		if l := lval_expr.as_lvalue() {
			for name in sa.names_modified_in_lvalue(l) {
				result << name
			}
		}
	}
	return result
}

// names_modified_in_lvalue returns NameExpr in lvalue
fn (sa SemanticAnalyzer) names_modified_in_lvalue(lval Lvalue) []NameExpr {
	if lval is NameExpr {
		return [lval]
	} else if lval is TupleExpr {
		mut result := []NameExpr{}
		for item in lval.items {
			if l := item.as_lvalue() {
				result << sa.names_modified_in_lvalue(l)
			}
		}
		return result
	}
	return []
}

// unwrap_final handles Final
fn (mut sa SemanticAnalyzer) unwrap_final(s AssignmentStmt) bool {
	// Check if assignment is wrapped in Final[]
	for lval in s.lvalues {
		if lval is NameExpr {
			// Check if type annotation contains Final
			if ann := s.type_annotation {
				if ann is UnboundType {
					if ann.name == 'Final' {
						return true
					}
				}
			}
		}
	}
	return false
}

// analyze_identity_global_assignment checks X = X
fn (sa SemanticAnalyzer) analyze_identity_global_assignment(s AssignmentStmt) bool {
	// Check if this is a self-assignment like X = X
	if s.lvalues.len != 1 {
		return false
	}

	lval := s.lvalues[0]
	if lval !is NameExpr {
		return false
	}

	if s.rvalue !is NameExpr {
		return false
	}

	lval_name := (lval as NameExpr).name
	rval_name := (s.rvalue as NameExpr).name

	// Check if it's the same name and already exists in global scope
	if lval_name == rval_name && lval_name in sa.globals.symbols {
		return true
	}

	return false
}

// analyze_rvalue analyzes the right-hand side of an assignment.
// This is a key part of semantic analysis where we traverse the rvalue AST
// to check for semantic validity and track any incomplete references (forward refs).
// Returns true if the analysis should be deferred due to incomplete references.
fn (mut sa SemanticAnalyzer) analyze_rvalue(mut s AssignmentStmt) !bool {
	// We track the state before analyzing the rvalue to detect if any new
	// incomplete references (forward references) are encountered.
	tag := sa.track_incomplete_refs()

	// The visitor pattern call handles the recursive traversal of the rvalue.
	// This is where the core semantic analysis of the expressions happens.
	s.rvalue.accept(mut sa)!

	if sa.found_incomplete_ref(tag) {
		// If the rvalue contains references to symbols that are not yet available,
		// we must mark the targets of this assignment as also incomplete.
		// This ensures that subsequent analysis steps that depend on these targets
		// will be correctly deferred until the references are resolved.
		for expr in sa.names_modified_by_assignment(s) {
			sa.mark_incomplete(expr.name, expr.base)
		}
		return true
	}

	// Additional analysis of types and semantic validity can be added here.
	// For global assignments, this may involve checking for special forms
	// like TypeVar, NewType, or TypeAlias definitions.
	return false
}

// qualified_name returns the qualified name
fn (sa SemanticAnalyzer) qualified_name(name string) string {
	if cur_type := sa.cur_type {
		return cur_type.fullname + '.' + name
	} else if sa.is_func_scope() {
		return name
	}
	return sa.cur_mod_id + '.' + name
}

// is_func_scope checks if we are in a function
fn (sa SemanticAnalyzer) is_func_scope() bool {
	scope_type := sa.scope_stack.last()
	return scope_type in [scope_func, scope_comprehension]
}

// is_class_scope checks if we are in a class

// is_async_context checks if we are inside an async function
fn (sa SemanticAnalyzer) is_async_context() bool {
	if sa.function_stack.len == 0 {
		return false
	}
	last := sa.function_stack.last()
	if last is FuncDef {
		return (last as FuncDef).is_coroutine
	}
	if last is Decorator {
		return (last as Decorator).func.is_coroutine
	}
	return false
}

fn (sa SemanticAnalyzer) is_class_scope() bool {
	return sa.cur_type != none && !sa.is_func_scope()
}

// is_module_scope checks if we are in a module
fn (sa SemanticAnalyzer) is_module_scope() bool {
	return !sa.is_class_scope() && !sa.is_func_scope()
}

// is_core_builtin_class checks if the class is a basic builtin
fn (sa SemanticAnalyzer) is_core_builtin_class(defn ClassDef) bool {
	return sa.cur_mod_id == 'builtins' && defn.name in core_builtin_classes
}

// recurse_into_functions checks if we should recursively traverse functions
fn (sa SemanticAnalyzer) recurse_into_functions() bool {
	return sa.recurse_into_function_bodies || sa.function_stack.len > 0
}

// enter_class enters a class
fn (mut sa SemanticAnalyzer) enter_class(info &TypeInfo) {
	sa.type_stack << sa.cur_type
	sa.locals << none
	sa.scope_stack << scope_class
	sa.block_depth << -1
	sa.loop_depth << [0]
	sa.cur_type = info
	sa.missing_names << map[string]bool{}
}

// leave_class exits a class
fn (mut sa SemanticAnalyzer) leave_class() {
	sa.block_depth.pop()
	sa.loop_depth.pop()
	sa.locals.pop()
	sa.scope_stack.pop()
	sa.cur_type = sa.type_stack.pop()
	sa.missing_names.pop()
}

// add_function_to_symbol_table adds a function to the symbol table
fn (mut sa SemanticAnalyzer) add_function_to_symbol_table(mut func_def FuncDef) {
	if sa.is_class_scope() {
		func_def.info = sa.cur_type
	}
	func_def.fullname = sa.qualified_name(func_def.name)
	sa.add_symbol(func_def.name, SymbolNodeRef(*func_def), func_def.get_context(), true,
		false, true)
}

// add_symbol adds a symbol
pub fn (mut sa SemanticAnalyzer) add_symbol(name string, node SymbolNodeRef, context Context, module_public bool, module_hidden bool, can_defer bool) bool {
	// Check if symbol already exists in current scope
	if sa.locals.len > 0 {
		last_idx := sa.locals.len - 1
		if mut locals := sa.locals[last_idx] {
			if name in locals.symbols {
				// Symbol already defined in current scope
				return false
			}
			locals.symbols[name] = SymbolTableNode{
				kind: 0 // LDEF for local
				node: node
			}
			sa.locals[last_idx] = locals // Re-assign back to the array!
			return true
		}
	}

	// Add to global scope
	if name in sa.globals.symbols {
		existing := sa.globals.symbols[name]
		if existing.node != none {
			sa.fail('Name "${name}" already defined', context, false, false, none)
			return false
		}
	}

	sa.globals.symbols[name] = SymbolTableNode{
		kind: 0 // GDEF for global
		node: node
	}
	return true
}

// add_imported_symbol adds an imported symbol
fn (mut sa SemanticAnalyzer) add_imported_symbol(name string, node SymbolTableNode, context ImportBase, module_public bool, module_hidden bool) {
	// Set module visibility flags
	mut sym := node
	sym.module_public = module_public
	sym.module_hidden = module_hidden

	// Add to current scope
	if sa.locals.len > 0 {
		if mut locals := sa.locals.last() {
			locals.symbols[name] = sym
			return
		}
	}

	// Add to global scope
	sa.globals.symbols[name] = sym
}

// add_unknown_imported_symbol adds an unknown imported symbol
fn (mut sa SemanticAnalyzer) add_unknown_imported_symbol(name string, context NodeBase, target_name string, module_public bool, module_hidden bool) {
	// Create a placeholder for unknown import
	any_type := AnyType{
		type_of_any: TypeOfAny.from_error
	}

	// Create a Var node with Any type
	mut var := Var{
		name:  name
		type_: any_type
	}
	var.fullname = target_name

	sym := SymbolTableNode{
		kind:          0
		node:          var
		module_public: module_public
		module_hidden: module_hidden
	}

	// Add to current scope
	if sa.locals.len > 0 {
		if locals := sa.locals.last() {
			_ = locals
			return
		}
	}

	// Add to global scope
	sa.globals.symbols[name] = sym
}

// report_missing_module_attribute reports a missing module attribute
fn (mut sa SemanticAnalyzer) report_missing_module_attribute(module_id string, source_id string, imported_id string, context NodeBase) {
	sa.fail('Module "${module_id}" has no attribute "${source_id}"', context.get_context(),
		false, false, none)
}

// correct_relative_import corrects a relative import
fn (sa SemanticAnalyzer) correct_relative_import(node ImportFrom) string {
	// Handle relative imports
	mut mod_id := node.id
	if node.relative > 0 {
		// Relative import - prepend current module path
		parts := sa.cur_mod_id.split('.')
		if node.relative <= parts.len {
			base_parts := parts[..parts.len - node.relative + 1]
			if mod_id.len > 0 {
				mod_id = base_parts.join('.') + '.' + mod_id
			} else {
				mod_id = base_parts.join('.')
			}
		}
	}
	return mod_id
}

// set_future_import_flags sets future import flags
fn (mut sa SemanticAnalyzer) set_future_import_flags(fullname string) {
	if flag := future_imports[fullname] {
		sa.future_import_flags[flag] = true
	}
}

// push_type_args adds type args
fn (mut sa SemanticAnalyzer) push_type_args(type_args []TypeParam, context NodeBase) ?[]string {
	if type_args.len == 0 {
		return []string{}
	}

	mut names := []string{}
	for ta in type_args {
		names << ta.name

		// Add type variable to scope
		// Add type variable to scope
		tvar := TypeVarType{
			name:        ta.name
			upper_bound: ta.upper_bound or {
				AnyType{
					type_of_any: TypeOfAny.unannotated
				}
			}
		}

		sa.tvar_scope.bind_existing(tvar)
	}

	return names
}

// pop_type_args removes type args
fn (mut sa SemanticAnalyzer) pop_type_args(type_args []TypeParam) {
	for ta in type_args {
		sa.tvar_scope.scope.delete(ta.name)
	}
}

// update_function_type_variables updates function type variables
fn (mut sa SemanticAnalyzer) update_function_type_variables(fun_type CallableType, defn FuncItem) bool {
	// Process type variables from function signature
	if fun_type.variables.len > 0 {
		for tvar in fun_type.variables {
			if tvar is TypeVarType {
				sa.tvar_scope.bind_existing(tvar)
			}
		}
		return true
	}
	return false
}

// analyze_function_body analyzes a function body
fn (mut sa SemanticAnalyzer) analyze_function_body(mut defn FuncItem) ! {
	// Enter function scope
	sa.scope_stack << scope_func
	sa.block_depth << 0
	sa.loop_depth << 0
	sa.locals << SymbolTable{
		symbols: map[string]SymbolTableNode{}
	}
	sa.missing_names << map[string]bool{}

	// Add function arguments to scope
	match mut defn {
		FuncDef {
			for mut arg in defn.arguments {
				mut var := Var{
					name:  arg.variable.name
					type_: arg.variable.type_
				}
				var.fullname = sa.qualified_name(arg.variable.name)
				sa.add_symbol(arg.variable.name, SymbolNodeRef(var), arg.variable.get_context(),
					true, false, true)
			}
		}
		else {}
	}

	// Analyze function body
	match mut defn {
		FuncDef {
			defn.body.accept(mut sa)!
		}
		Decorator {
			defn.func.body.accept(mut sa)!
		}
		OverloadedFuncDef {
			// No body
		}
		LambdaExpr {
			defn.body.accept(mut sa)!
		}
	}

	// Leave function scope
	sa.scope_stack.pop()
	sa.locals.pop()
	sa.missing_names.pop()
	sa.block_depth.pop()
	sa.loop_depth.pop()
}

pub fn (mut sa SemanticAnalyzer) get_tvar_scope() &TypeVarLikeScope {
	return &sa.tvar_scope
}

pub fn (mut sa SemanticAnalyzer) named_type(fullname string, args []MypyTypeNode) &Instance {
	res := sa.named_type_or_none(fullname, args)
	if r := res {
		return r
	}
	// Fallback to Any if not found
	return &Instance{
		typ:  none
		args: args
	}
}

pub fn (mut sa SemanticAnalyzer) named_type_or_none(fullname string, args []MypyTypeNode) ?&Instance {
	sym := sa.lookup_fully_qualified_or_none(fullname) or { return none }
	node := sym.node or { return none }
	if node is TypeInfo {
		return &Instance{
			typ:  unsafe { &node }
			args: args
		}
	}
	return none
}

pub fn (mut sa SemanticAnalyzer) anal_type(typ MypyTypeNode, tvar_scope ?&TypeVarLikeScope, allow_tuple_literal bool, allow_unbound_tvars bool, allow_typed_dict_special_forms bool, allow_placeholder bool, report_invalid_types bool, prohibit_self_type ?string, prohibit_special_class_field_types ?string) ?MypyTypeNode {
	mut ta := TypeAnalyser{
		api:                                sa
		tvar_scope:                         if ts := tvar_scope { ts } else { &sa.tvar_scope }
		plugin:                             sa.plugin
		options:                            sa.options
		cur_mod_node:                       sa.cur_mod_node or { &MypyFile{} }
		is_typeshed_stub:                   sa.is_typeshed_stub_file
		allow_tuple_literal:                allow_tuple_literal
		allow_unbound_tvars:                allow_unbound_tvars
		allow_typed_dict_special_forms:     allow_typed_dict_special_forms
		allow_placeholder:                  allow_placeholder
		report_invalid_types:               report_invalid_types
		prohibit_self_type:                 prohibit_self_type
		prohibit_special_class_field_types: prohibit_special_class_field_types
	}
	res := ta.anal_type(typ, false) or { return none }
	return res
}

pub fn (mut sa SemanticAnalyzer) get_and_bind_all_tvars(type_exprs []Expression) []MypyTypeNode {
	mut res := []MypyTypeNode{}
	for expr in type_exprs {
		match expr {
			TypeVarExpr {
				tv_node := TypeVarType{
					name:        expr.name
					fullname:    expr.fullname
					id:          expr.id
					values:      expr.values
					upper_bound: expr.upper_bound
					variance:    expr.variance
					default:     expr.default_
					line:        expr.base.line
				}
				sa.tvar_scope.bind_existing(TypeVarLikeType(tv_node))
				res << MypyTypeNode(tv_node)
			}
			ParamSpecExpr {
				ps_node := ParamSpecType{
					name:        expr.name
					fullname:    expr.fullname
					id:          expr.id
					upper_bound: expr.upper_bound
					default:     expr.default_
					line:        expr.base.line
				}
				sa.tvar_scope.bind_existing(TypeVarLikeType(ps_node))
				res << MypyTypeNode(ps_node)
			}
			TypeVarTupleExpr {
				tvt_node := TypeVarTupleType{
					name:        expr.name
					fullname:    expr.fullname
					id:          expr.id
					upper_bound: expr.upper_bound
					default:     expr.default_
					line:        expr.base.line
				}
				sa.tvar_scope.bind_existing(TypeVarLikeType(tvt_node))
				res << MypyTypeNode(tvt_node)
			}
			else {}
		}
	}
	return res
}

pub fn (mut sa SemanticAnalyzer) basic_new_typeinfo(name string, basetype_or_fallback &Instance, line int) &TypeInfo {
	mut info := &TypeInfo{
		name:        name
		fullname:    sa.qualified_name(name)
		module_name: sa.cur_mod_id
		names:       SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
	}
	info.bases = [
		basetype_or_fallback.copy_modified(basetype_or_fallback.args, basetype_or_fallback.last_known_value),
	]
	info.mro = [info]
	return info
}

pub fn (mut sa SemanticAnalyzer) schedule_patch(priority int, patch fn ()) {
	sa.patches << PatchEntry{
		priority: priority
		callback: patch
	}
}

pub fn (mut sa SemanticAnalyzer) add_symbol_table_node(name string, symbol &SymbolTableNode) bool {
	if sa.is_class_scope() {
		if mut ct := sa.cur_type {
			ct.names.symbols[name] = *symbol
			return true
		}
	}

	if sa.locals.len > 0 {
		if mut locals := sa.locals.last() {
			locals.symbols[name] = *symbol
			return true
		}
	}

	sa.globals.symbols[name] = *symbol
	return true
}

pub fn (mut sa SemanticAnalyzer) current_symbol_table() map[string]&SymbolTableNode {
	mut res := map[string]&SymbolTableNode{}
	if sa.is_class_scope() {
		if mut ct := sa.cur_type {
			for k, v in ct.names.symbols {
				res[k] = unsafe { &ct.names.symbols[k] }
			}
			return res
		}
	}

	if sa.locals.len > 0 {
		if mut locals := sa.locals.last() {
			for k, v in locals.symbols {
				res[k] = unsafe { &locals.symbols[k] }
			}
			return res
		}
	}

	for k, v in sa.globals.symbols {
		res[k] = unsafe { &sa.globals.symbols[k] }
	}
	return res
}

pub fn (mut sa SemanticAnalyzer) add_symbol_skip_local(name string, node SymbolNodeRef) {
	sa.globals.symbols[name] = SymbolTableNode{
		kind: gdef
		node: node
	}
}

pub fn (mut sa SemanticAnalyzer) parse_bool(expr Expression) ?bool {
	return parse_bool_helper(expr)
}

pub fn (mut sa SemanticAnalyzer) process_placeholder(name ?string, kind string, ctx Context, force_progress bool) {
	if n := name {
		p := PlaceholderNode{
			fullname:         sa.qualified_name(n)
			node:             SymbolNodeRef(Var{
				name: n
			})
			becomes_typeinfo: kind == 'class'
		}
		sa.add_symbol(n, SymbolNodeRef(p), ctx, true, false, true)
	}
	sa.record_incomplete_ref()
	if force_progress {
		sa.progress = true
	}
}

pub fn (mut sa SemanticAnalyzer) get_plugin() &Plugin {
	return &sa.plugin
}

pub fn (mut sa SemanticAnalyzer) lookup_fully_qualified(fullname string) &SymbolTableNode {
	res := lookup_fully_qualified(fullname, sa.modules)
	if r := res {
		return unsafe { &r }
	}
	panic('Could not find ' + fullname)
}

pub fn (mut sa SemanticAnalyzer) lookup_fully_qualified_or_none(fullname string) ?&SymbolTableNode {
	res := lookup_fully_qualified(fullname, sa.modules)
	if r := res {
		return unsafe { &r }
	}
	return none
}

pub fn (mut sa SemanticAnalyzer) note(msg string, ctx Context, code ?&ErrorCode) {
	sa.errors.report(ctx.line, ctx.column, msg, none, 'note', false, false)
}

pub fn (mut sa SemanticAnalyzer) incomplete_feature_enabled(feature string, ctx Context) bool {
	return false
}

pub fn (mut sa SemanticAnalyzer) record_incomplete_ref() {
	if sa.missing_names.len > 0 {
		// Mark current context as incomplete
		sa.missing_names.last()[incomplete_ref_marker] = true
	}
	sa.incomplete = true
}

pub fn (sa SemanticAnalyzer) is_incomplete_namespace(fullname string) bool {
	return sa.incomplete_namespaces[fullname]
}

pub fn (sa SemanticAnalyzer) is_future_flag_set(flag string) bool {
	return sa.future_import_flags[flag]
}

pub fn (sa SemanticAnalyzer) get_current_type() ?&TypeInfo {
	if t := sa.cur_type {
		return unsafe { &t }
	}
	return none
}

pub fn (mut sa SemanticAnalyzer) defer(debug_context ?Context, force_progress bool) {
	sa.deferred = true
	sa.progress = sa.progress || force_progress
}

fn (mut sa SemanticAnalyzer) analyze_base_classes(mut defn ClassDef) ! {
	mut info := defn.info or { return }
	mut bases := []Instance{}

	for mut base_expr in defn.base_type_exprs {
		// 1. Convert expression to unanalyzed type
		unanalyzed := expr_to_unanalyzed_type(base_expr, sa.options, false, none, false,
			none) or {
			sa.fail('Invalid base class', base_expr.get_context(), false, false, none)
			continue
		}

		// 2. Analyze the type
		analyzed := sa.anal_type(unanalyzed, none, false, false, false, true, true, none,
			none)
		if typ := analyzed {
			if typ is Instance {
				bases << (typ as Instance)
			} else if typ is AnyType {
				// Handle Any as base class if needed, or just skip
			} else {
				sa.fail('Invalid base class', base_expr.get_context(), false, false, none)
			}
		} else {
			// Resolution failed, likely deferred
		}
	}

	// If no bases and not builtins.object itself, add builtins.object
	if bases.len == 0 && info.fullname != 'builtins.object' {
		if obj := sa.named_type_or_none('builtins.object', []) {
			bases << obj.copy_modified(obj.args, obj.last_known_value)
		}
	}

	info.bases = bases
}

pub fn (mut sa SemanticAnalyzer) fail(msg string, ctx Context, serious bool, blocker bool, code ?&ErrorCode) {
	mut severity := 'error'
	if !serious {
		severity = 'note'
	}
	sa.errors.report(ctx.line, ctx.column, msg, none, severity, blocker, false)
}

pub fn (mut sa SemanticAnalyzer) report_hang() {
	sa.errors.report(0, 0, 'Semantic analysis failed to converge after ${max_iterations} iterations',
		none, 'error', true, false)
}

fn (mut sa SemanticAnalyzer) prepare_class_def(mut defn ClassDef) ! {
	// Create TypeInfo if not exists
	if defn.info == none {
		fullname := sa.qualified_name(defn.name)
		mut info := new_type_info(mut sa.globals, &defn, sa.cur_mod_id)
		info.fullname = fullname
		defn.info = info
	}

	// Process base classes
	for mut base_expr in defn.base_type_exprs {
		base_expr.accept(mut sa)!
	}

	// Process decorators
	for mut dec in defn.decorators {
		dec.accept(mut sa)!
	}
}

// setup_type_vars sets up type variables
fn (mut sa SemanticAnalyzer) setup_type_vars(defn ClassDef, tvar_defs []TypeVarLikeType) {
	// Add type variables from class definition to scope
	for tvar_def in tvar_defs {
		if tvar_def is TypeVarType {
			sa.tvar_scope.bind_existing(tvar_def)
		}
	}
}

// mark_incomplete marks an incomplete definition
fn (mut sa SemanticAnalyzer) mark_incomplete(name string, node NodeBase) {
	sa.defer(node.get_context(), false)
	sa.missing_names.last()[name] = true
}

// track_incomplete_refs tracks incomplete references
fn (mut sa SemanticAnalyzer) track_incomplete_refs() int {
	// Return current count of missing names
	return sa.missing_names.last().len
}

// found_incomplete_ref checks for the presence of incomplete references
fn (sa SemanticAnalyzer) found_incomplete_ref(tag int) bool {
	// Check if new incomplete refs were added
	return sa.missing_names.last().len > tag
}

// new_type_info вЂ” helper for creating TypeInfo
pub fn new_type_info(mut _ SymbolTable, defn &ClassDef, module_name string) &TypeInfo {
	mut info := &TypeInfo{
		name:        defn.name
		fullname:    if module_name.len > 0 { module_name + '.' + defn.name } else { defn.name }
		module_name: module_name
		names:       SymbolTable{
			symbols: map[string]SymbolTableNode{}
		}
		defn:        defn
	}
	info.mro = [info]
	return info
}

fn (mut sa SemanticAnalyzer) analyze_typevar_declaration(s &AssignmentStmt) bool {
	if s.lvalues.len != 1 || s.lvalues[0] !is NameExpr {
		return false
	}
	name := (s.lvalues[0] as NameExpr).name
	rvalue := s.rvalue
	if rvalue is CallExpr {
		call := rvalue as CallExpr
		callee := call.callee
		if callee is NameExpr {
			if (callee as NameExpr).fullname in ['typing.TypeVar', 'typing_extensions.TypeVar'] {
				mut tv := &TypeVarExpr{
					name:        name
					fullname:    sa.qualified_name(name)
					upper_bound: AnyType{
						type_of_any: .from_another_any
					}
					default_:    AnyType{
						type_of_any: .from_another_any
					}
				}
				sa.add_symbol(name, SymbolNodeRef(tv), s.get_context(), true, false, true)
				return true
			}
		}
	}
	return false
}

fn (mut sa SemanticAnalyzer) analyze_paramspec_declaration(s &AssignmentStmt) bool {
	if s.lvalues.len != 1 || s.lvalues[0] !is NameExpr {
		return false
	}
	name := (s.lvalues[0] as NameExpr).name
	rvalue := s.rvalue
	if rvalue is CallExpr {
		call := rvalue as CallExpr
		callee := call.callee
		if callee is NameExpr {
			if (callee as NameExpr).fullname in ['typing.ParamSpec', 'typing_extensions.ParamSpec'] {
				mut ps := &ParamSpecExpr{
					name:        name
					fullname:    sa.qualified_name(name)
					upper_bound: AnyType{
						type_of_any: .from_another_any
					}
					default_:    AnyType{
						type_of_any: .from_another_any
					}
				}
				sa.add_symbol(name, SymbolNodeRef(ps), s.get_context(), true, false, true)
				return true
			}
		}
	}
	return false
}

fn (mut sa SemanticAnalyzer) analyze_typevartuple_declaration(s &AssignmentStmt) bool {
	if s.lvalues.len != 1 || s.lvalues[0] !is NameExpr {
		return false
	}
	name := (s.lvalues[0] as NameExpr).name
	rvalue := s.rvalue
	if rvalue is CallExpr {
		call := rvalue as CallExpr
		callee := call.callee
		if callee is NameExpr {
			if (callee as NameExpr).fullname in ['typing.TypeVarTuple',
				'typing_extensions.TypeVarTuple'] {
				mut tvt := &TypeVarTupleExpr{
					name:        name
					fullname:    sa.qualified_name(name)
					upper_bound: AnyType{
						type_of_any: .from_another_any
					}
					default_:    AnyType{
						type_of_any: .from_another_any
					}
				}
				sa.add_symbol(name, SymbolNodeRef(tvt), s.get_context(), true, false,
					true)
				return true
			}
		}
	}
	return false
}

fn (mut sa SemanticAnalyzer) analyze_typealias_declaration(s &AssignmentStmt) bool {
	if s.is_alias_def {
		if s.lvalues.len != 1 || s.lvalues[0] !is NameExpr {
			return false
		}
		name := (s.lvalues[0] as NameExpr).name

		mut alias := &TypeAlias{
			name:     name
			fullname: sa.qualified_name(name)
			target:   AnyType{
				type_of_any: .from_another_any
			}
		}
		sa.add_symbol(name, SymbolNodeRef(alias), s.get_context(), true, false, true)
		return true
	}
	return false
}

pub fn (mut sa SemanticAnalyzer) check_for_special_forms(mut s AssignmentStmt) bool {
	if s.lvalues.len != 1 {
		return false
	}
	lvalue := s.lvalues[0]
	if lvalue !is NameExpr {
		return false
	}

	if sa.analyze_typevar_declaration(s) {
		return true
	}
	if sa.analyze_paramspec_declaration(s) {
		return true
	}
	if sa.analyze_typevartuple_declaration(s) {
		return true
	}
	if sa.analyze_typealias_declaration(s) {
		return true
	}

	return false
}

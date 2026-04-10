// checker.v — Mypy type checker
// Translated from mypy/checker.py
// Note: this is a very large file (~4000 lines), main structures and key functions are translated

module mypy

// Constants
pub const default_last_pass = 2
pub const max_precise_tuple_size = 8

// DeferredNodeType — type for deferred node
pub type DeferredNodeType = FuncDef | OverloadedFuncDef | Decorator
pub type OverloadPart = OverloadedFuncDef

// FineGrainedDeferredNodeType — type for fine-grained mode
pub type FineGrainedDeferredNodeType = FuncDef | MypyFile | OverloadedFuncDef

// DeferredNode — node deferred for processing in the next pass
pub struct DeferredNode {
pub:
	node            DeferredNodeType
	active_typeinfo ?TypeInfo
}

// FineGrainedDeferredNode — node for fine-grained mode
pub struct FineGrainedDeferredNode {
pub:
	node            FineGrainedDeferredNodeType
	active_typeinfo ?TypeInfo
}

// TypeMap — mapping of Expressions to types
pub type TypeMap = map[string]MypyTypeNode

// PartialTypeScope — scope for partial types
pub struct PartialTypeScope {
pub:
	map         map[string]NodeBase
	is_function bool
	is_local    bool
}

// TypeChecker — mypy type checker
pub struct TypeChecker {
pub mut:
	is_stub                  bool
	errors                   Errors
	msg                      MessageBuilder
	type_maps                []TypeMap
	all_type_maps            []TypeMap
	persistent_type_map      TypeMap
	binder                   ConditionalTypeBinder
	expr_checker             ExpressionChecker
	pattern_checker          PatternChecker
	tscope                   Scope
	scope                    CheckerScope
	active_type              ?&TypeInfo
	return_types             []MypyTypeNode
	dynamic_funcs            []bool
	partial_types            []PartialTypeScope
	partial_reported         map[string]bool
	widened_vars             []string
	globals                  SymbolTable
	modules                  map[string]&MypyFile
	deferred_nodes           []DeferredNode
	pass_num                 int
	last_pass                int
	current_node_deferred    bool
	is_typeshed_stub         bool
	options                  Options
	inferred_attribute_types ?map[string]MypyTypeNode
	no_partial_types         bool
	module_refs              map[string]bool
	var_decl_frames          map[string]map[int]bool
	plugin                   Plugin
	tree                     MypyFile
	path                     string
	unique_id                int
	is_final_def             bool
	overload_impl_stack      []OverloadPart
	checking_missing_await   bool
	allow_abstract_call      bool
	recurse_into_functions   bool
}

// new_type_checker creates a new TypeChecker
pub fn new_type_checker(errors Errors, modules map[string]&MypyFile, options Options, tree &MypyFile, path string, plugin Plugin) &TypeChecker {
	msg := MessageBuilder{
		errors:  &errors
		options: &options
		modules: map[string]&MypyFile{}
	}
	mut tc := &TypeChecker{
		is_stub:                  tree.is_stub
		errors:                   errors
		msg:                      msg
		type_maps:                [TypeMap{}]
		all_type_maps:            []TypeMap{}
		persistent_type_map:      TypeMap{}
		binder:                   *new_conditional_type_binder(&options)
		tscope:                   Scope{}
		scope:                    new_checker_scope(tree)
		active_type:              none
		return_types:             []MypyTypeNode{}
		dynamic_funcs:            []bool{}
		partial_types:            []PartialTypeScope{}
		partial_reported:         map[string]bool{}
		widened_vars:             []string{}
		globals:                  tree.names
		modules:                  modules
		deferred_nodes:           []DeferredNode{}
		pass_num:                 0
		last_pass:                default_last_pass
		current_node_deferred:    false
		is_typeshed_stub:         is_typeshed_file(none, path)
		options:                  options
		inferred_attribute_types: none
		no_partial_types:         false
		module_refs:              map[string]bool{}
		var_decl_frames:          map[string]map[int]bool{}
		plugin:                   plugin
		tree:                     tree
		path:                     path
		unique_id:                0
		is_final_def:             false
		overload_impl_stack:      []OverloadPart{}
		checking_missing_await:   false
		allow_abstract_call:      false
		recurse_into_functions:   true
	}

	tc.expr_checker = new_expression_checker(tc, msg, plugin)
	tc.pattern_checker = PatternChecker{
		chk:          tc
		type_context: []MypyTypeNode{}
	}
	return tc
}

// reset clears state for reuse
pub fn (mut tc TypeChecker) reset() {
	tc.partial_reported.clear()
	tc.module_refs.clear()
	tc.binder = *new_conditional_type_binder(&tc.options)
	tc.type_maps = [TypeMap{}]
	tc.all_type_maps = []TypeMap{}
	tc.deferred_nodes = []
	tc.partial_types = []
	tc.inferred_attribute_types = none
	tc.scope = new_checker_scope(tc.tree)
}

// check_first_pass checks the file in the first pass
pub fn (mut tc TypeChecker) check_first_pass() {
	tc.recurse_into_functions = true
	tc.errors.set_file(tc.path, tc.tree.fullname)

	for d in tc.tree.defs {
		tc.accept(d)
	}
}

// check_second_pass checks deferred nodes
pub fn (mut tc TypeChecker) check_second_pass() bool {
	tc.recurse_into_functions = true
	if tc.deferred_nodes.len == 0 {
		return false
	}
	tc.pass_num++
	mut todo := tc.deferred_nodes.clone()
	tc.deferred_nodes = []

	for item in todo {
		node := item.node
		if node is FuncDef {
			tc.accept(node)
		} else if node is Decorator {
			tc.accept(node)
		} else if node is OverloadedFuncDef {
			mut overloaded := node
			tc.visit_overloaded_func_def(mut overloaded) or {}
		}
	}
	return true
}

// check_top_level checks only the top level of a module
pub fn (mut tc TypeChecker) check_top_level(node &MypyFile) {
	tc.recurse_into_functions = false
	for d in node.defs {
		tc.accept(d)
	}
}

// accept accepts a node for checking
pub fn (mut tc TypeChecker) accept(stmt Statement) {
	mut stmt_mut := stmt
	stmt_mut.accept(mut tc) or { eprintln('### TC ACCEPT ERR: ${err}') }
}

// visit_func_def checks function definition
pub fn (mut tc TypeChecker) visit_func_def(mut defn FuncDef) !AnyNode {
	tc.scope.push_function(FuncItem(defn))
	tc.check_func_item(defn, defn.name)
	tc.scope.pop_function()
	return ''
}

// visit_class_def checks class definition
pub fn (mut tc TypeChecker) visit_class_def(mut defn ClassDef) !AnyNode {
	typ := defn.info or { return '' }

	old_active := tc.active_type
	tc.active_type = typ
	tc.scope.push_class(*typ)
	for mut stmt in defn.defs.body {
		stmt.accept(mut tc)!
	}
	tc.scope.pop_class()
	tc.active_type = old_active
	return ''
}

// check_func_item checks a function item
pub fn (mut tc TypeChecker) check_func_item(defn FuncItem, name string) {
	_ = name
	tc.dynamic_funcs << false

	if defn is FuncDef {
		mut fn_def := defn
		tc.check_func_def(mut fn_def, name)
	}

	tc.dynamic_funcs.pop()
}

// check_func_def checks function definition
fn (mut tc TypeChecker) check_func_def(mut defn FuncDef, name string) {
	_ = name
	tc.type_maps << TypeMap{}

	// Manually add parameters to the current type map
	for i, arg in defn.arguments {
		arg_name := arg.variable.name
		mut typ := ?MypyTypeNode(none)

		if t := arg.variable.type_ {
			typ = t
		} else if arg_name == 'self' || i == 0 {
			if active := tc.active_type {
				typ = MypyTypeNode(Instance{
					type_: active
					args:  []MypyTypeNode{}
				})
			}
		}

		if t := typ {
			tc.type_maps.last()[arg_name] = t

			// Store with correct location for persistent lookup
			ctx := arg.variable.get_context()
			pkey := '${ctx.line}:${ctx.column}:${arg_name}'
			tc.persistent_type_map[pkey] = t
		}
	}

	if typ := defn.type_ {
		if typ is CallableType {
			tc.return_types << typ.ret_type
		}
	}

	// Check function body
	defn.body.accept(mut tc) or {}

	if tc.return_types.len > 0 {
		tc.return_types.pop()
	}
	tc.all_type_maps << tc.type_maps.pop()
}

// visit_assignment_stmt checks assignment
pub fn (mut tc TypeChecker) visit_assignment_stmt(mut s AssignmentStmt) !AnyNode {
	mut rvalue_type := tc.expr_checker.accept(s.rvalue)

	if ann := s.type_annotation {
		rvalue_type = ann
	}

	// Check each lvalue
	for mut lvalue in s.lvalues {
		if mut lval := lvalue.as_lvalue() {
			tc.check_assignment(mut lval, s.rvalue, rvalue_type)
		}
	}
	return ''
}

// check_assignment checks assignment
fn (mut tc TypeChecker) check_assignment(mut lvalue Lvalue, rvalue Expression, rvalue_type MypyTypeNode) {
	// check_assignment logic moved to check_simple_assignment to avoid duplication
	tc.check_simple_assignment(mut lvalue, rvalue, rvalue_type)
}


// check_unpacking_assignment handles multiple assignment unpacking
fn (mut tc TypeChecker) check_unpacking_assignment(mut lvalue Lvalue, items []Expression, rvalue Expression, rvalue_type MypyTypeNode) {
	tc.store_type(lvalue.as_expression(), rvalue_type)
	proper_rvalue := get_proper_type(rvalue_type)

	mut star_index := -1
	for i, item in items {
		if item is StarExpr {
			if star_index != -1 {
				tc.msg.fail('Two starred expressions in assignment', rvalue.get_context(), false, false, none)
			}
			star_index = i
		}
	}

	match proper_rvalue {
		TupleType {
			if star_index == -1 {
				if items.len != proper_rvalue.items.len {
					tc.msg.fail('Incompatible number of values to unpack (expected ${items.len}, got ${proper_rvalue.items.len})', rvalue.get_context(), false, false, none)
				}
				for i in 0 .. items.len {
					mut item := items[i]
					mut item_lval := item.as_lvalue() or { continue }
					item_type := if i < proper_rvalue.items.len {
						proper_rvalue.items[i]
					} else {
						MypyTypeNode(AnyType{ type_of_any: .from_untyped_call })
					}
					tc.check_assignment(mut item_lval, item, item_type)
				}
			} else {
				if proper_rvalue.items.len < items.len - 1 {
					tc.msg.fail('Not enough values to unpack (expected at least ${items.len - 1}, got ${proper_rvalue.items.len})', rvalue.get_context(), false, false, none)
				}
				// Before star
				for i in 0 .. star_index {
					mut item := items[i]
					mut item_lval := item.as_lvalue() or { continue }
					tc.check_assignment(mut item_lval, item, proper_rvalue.items[i])
				}
				// The star itself
				star_len := proper_rvalue.items.len - (items.len - 1)
				mut starred_items := []MypyTypeNode{}
				for i in 0 .. star_len {
					starred_items << proper_rvalue.items[star_index + i]
				}

				mut star_expr_node := items[star_index]
				if star_expr_node is StarExpr {
					mut star_expr := star_expr_node as StarExpr
					mut star_lval := Expression(star_expr).as_lvalue() or { panic('unreachable') }
					// For now, starred assignment gets a List or Tuple of the items
					// Mypy typically uses a List for the starred part
					tc.check_assignment(mut star_lval, Expression(star_expr), MypyTypeNode(Instance{
						type_name: 'builtins.list'
						args: [starred_items[0] or { MypyTypeNode(AnyType{type_of_any: .from_untyped_call}) }]
					}))
				}

				// After star
				for i in star_index + 1 .. items.len {
					mut item := items[i]
					mut item_lval := item.as_lvalue() or { continue }
					tc.check_assignment(mut item_lval, item, proper_rvalue.items[proper_rvalue.items.len - (items.len - i)])
				}
			}
		}
		Instance {
			if (proper_rvalue.type_name == 'builtins.list' || proper_rvalue.type_name == 'builtins.tuple' || proper_rvalue.type_name == 'builtins.dict') && proper_rvalue.args.len > 0 {
				item_type := proper_rvalue.args[0]
				for item_ in items {
					mut item := item_
					if item is StarExpr {
						mut star_expr := item as StarExpr
						mut star_lval := Expression(star_expr).as_lvalue() or { continue }
						// For list/tuple/dict, starred version is a list of the same element type
						mut list_type := MypyTypeNode(Instance{
							type_name: 'builtins.list'
							args: [item_type]
						})
						tc.check_assignment(mut star_lval, Expression(star_expr), list_type)
					} else if mut item_lval := item.as_lvalue() {
						tc.check_assignment(mut item_lval, item, item_type)
					}
				}
			} else {
				tc.msg.fail('"' + proper_rvalue.type_name + '" object is not iterable', rvalue.get_context(), false, false, none)
			}
		}
		AnyType {
			for item_ in items {
				mut item := item_
				if item is StarExpr {
					mut star_expr := item as StarExpr
					mut star_lval := Expression(star_expr).as_lvalue() or { continue }
					tc.check_assignment(mut star_lval, Expression(star_expr), proper_rvalue)
				} else if mut item_lval := item.as_lvalue() {
					tc.check_assignment(mut item_lval, item, proper_rvalue)
				}
			}
		}
		else {
			tc.msg.fail('object is not iterable', rvalue.get_context(), false, false, none)
		}
	}
}

// check_simple_assignment checks simple assignment
fn (mut tc TypeChecker) check_simple_assignment(mut lvalue Lvalue, rvalue Expression, rvalue_type MypyTypeNode) {
	// Handle different Lvalue variants
	match mut lvalue {
		NameExpr {
			tc.store_type(Expression(lvalue), rvalue_type)
			if mut node := lvalue.node {
				if mut node is Var {
					if target_type := node.type_ {
						tc.check_subtype(rvalue_type, target_type, rvalue.get_context(),
							'Incompatible types in assignment')
					} else {
						node.type_ = rvalue_type
					}
				}
			}
		}
		MemberExpr {
			tc.store_type(Expression(lvalue), rvalue_type)
			// If assigning to self.name, register it in the class TypeInfo
			if mut active := tc.active_type {
				if lvalue.expr is NameExpr {
					base_name := (lvalue.expr as NameExpr).name
					if base_name.trim_space() == "self" {
						if lvalue.name !in active.names.symbols {
							mut v := Var{
								name:     lvalue.name
								fullname: active.fullname + "." + lvalue.name
								type_:    rvalue_type
							}
							active.names.symbols[lvalue.name] = SymbolTableNode{
								kind: mdef
								node: SymbolNodeRef(v)
							}
						}
					}
				}
			}

			member_type := tc.expr_checker.visit_member_expr(lvalue, true)
			if member_type is AnyType {
				if member_type.type_of_any != .from_error {
					tc.check_subtype(rvalue_type, member_type, rvalue.get_context(), 'Incompatible types in assignment')
				}
			} else {
				tc.check_subtype(rvalue_type, member_type, rvalue.get_context(), 'Incompatible types in assignment')
			}
		}
		TupleExpr {
			tc.check_unpacking_assignment(mut lvalue, lvalue.items, rvalue, rvalue_type)
		}
		ListExpr {
			tc.check_unpacking_assignment(mut lvalue, lvalue.items, rvalue, rvalue_type)
		}
		StarExpr {
			tc.store_type(Expression(lvalue), rvalue_type)
			if mut inner_lval := lvalue.expr.as_lvalue() {
				// The rvalue_type here is already the list type
				tc.check_assignment(mut inner_lval, lvalue.expr, rvalue_type)
			}
		}
		IndexExpr {
			tc.store_type(Expression(lvalue), rvalue_type)
			base_type := tc.expr_checker.accept(lvalue.base_)
			proper_base := get_proper_type(base_type)
			if proper_base is TypedDictType {
				if lvalue.index is StrExpr {
					key := (lvalue.index as StrExpr).value
					if key in proper_base.items {
						if key in proper_base.readonly_keys {
							tc.msg.fail("Cannot assign to read-only TypedDict key '" + key + "'",
								lvalue.get_context(), false, false, none)
						}
						item_type := proper_base.items[key] or {
							MypyTypeNode(AnyType{
								type_of_any: .from_error
							})
						}
						tc.check_subtype(rvalue_type, item_type, rvalue.get_context(),
							'Incompatible types in assignment')
					} else {
						tc.msg.fail("TypedDict has no key '" + key + "'", lvalue.get_context(),
							false, false, none)
					}
				} else {
					tc.msg.fail('TypedDict index must be a string literal', lvalue.get_context(),
						false, false, none)
				}
			} else {
				tc.expr_checker.check_method_call_by_name('__setitem__', base_type, [
					lvalue.index,
					rvalue,
				], [
					.arg_pos,
					.arg_pos,
				], lvalue.base)
			}
		}
	}
}


// visit_return_stmt checks return
pub fn (mut tc TypeChecker) visit_return_stmt(mut s ReturnStmt) !AnyNode {
	if expr := s.expr {
		tc.expr_checker.accept(expr)
		if tc.return_types.len > 0 {
			ret_type := tc.return_types.last()
			expr_type := tc.lookup_type_or_none(expr)
			if expr_type != none {
				tc.check_subtype(expr_type, ret_type, s.base.ctx, 'Incompatible return value type')
			}
		}
	}
	tc.binder.unreachable()
	return ''
}

// visit_if_stmt checks if
pub fn (mut tc TypeChecker) visit_if_stmt(mut s IfStmt) !AnyNode {
	for expr in s.expr {
		tc.expr_checker.accept(expr)
	}
	for mut body in s.body {
		body.accept(mut tc) or {}
	}
	if mut eb := s.else_body {
		eb.accept(mut tc) or {}
	}
	return ''
}

// visit_while_stmt checks while
pub fn (mut tc TypeChecker) visit_while_stmt(mut s WhileStmt) !AnyNode {
	tc.expr_checker.accept(s.expr)
	s.body.accept(mut tc) or {}
	if mut eb := s.else_body {
		eb.accept(mut tc) or {}
	}
	return ''
}

// visit_for_stmt checks for
pub fn (mut tc TypeChecker) visit_for_stmt(mut s ForStmt) !AnyNode {
	iterable_type := tc.expr_checker.accept(s.expr)

	// Determine item type for loop variable
	mut item_type := MypyTypeNode(AnyType{
		type_of_any: .from_untyped_call
	})
	proper_iterable := get_proper_type(iterable_type)
	if proper_iterable is Instance {
		if proper_iterable.type_name == 'builtins.list' && proper_iterable.args.len > 0 {
			item_type = proper_iterable.args[0]
		}
	}

	// Check loop variable (index)
	if mut lval := s.index.as_lvalue() {
		tc.check_assignment(mut lval, s.expr, item_type)
	}

	s.body.accept(mut tc) or {}
	if mut eb := s.else_body {
		eb.accept(mut tc) or {}
	}
	return ''
}

// visit_try_stmt checks try
pub fn (mut tc TypeChecker) visit_try_stmt(mut s TryStmt) !AnyNode {
	s.body.accept(mut tc) or {}
	for i in 0 .. s.types.len {
		if t := s.types[i] {
			tc.expr_checker.accept(t)
		}
		s.handlers[i].accept(mut tc) or {}
	}
	if mut eb := s.else_body {
		eb.accept(mut tc) or {}
	}
	if mut fb := s.finally_body {
		fb.accept(mut tc) or {}
	}
	return ''
}

// visit_block checks block
pub fn (mut tc TypeChecker) visit_block(mut b Block) !AnyNode {
	if b.is_unreachable {
		tc.binder.unreachable()
		return ''
	}
	for mut s in b.body {
		s.accept(mut tc) or { eprintln('### STMT ACCEPT ERR: ${err}') }
	}
	return ''
}

// visit_decorator checks decorator
pub fn (mut tc TypeChecker) visit_decorator(mut e Decorator) !AnyNode {
	tc.visit_func_def(mut e.func) or {}
	return ''
}

// visit_expression_stmt checks Expression statement
pub fn (mut tc TypeChecker) visit_expression_stmt(mut s ExpressionStmt) !AnyNode {
	tc.expr_checker.accept(s.expr)
	return ''
}

// visit_break_stmt checks break
pub fn (mut tc TypeChecker) visit_break_stmt(mut s BreakStmt) !AnyNode {
	tc.binder.handle_break()
	return ''
}

// visit_continue_stmt checks continue
pub fn (mut tc TypeChecker) visit_continue_stmt(mut s ContinueStmt) !AnyNode {
	tc.binder.handle_continue()
	return ''
}

// visit_pass_stmt checks pass
pub fn (mut tc TypeChecker) visit_pass_stmt(mut s PassStmt) !AnyNode {
	// Do nothing
	return ''
}

// find_isinstance_check finds isinstance checks
pub fn (tc TypeChecker) find_isinstance_check(node Expression) (TypeMap, TypeMap) {
	match node {
		CallExpr {
			if !tc.is_isinstance_call(node) {
				return TypeMap{}, TypeMap{}
			}
			if node.args.len != 2 {
				return TypeMap{}, TypeMap{}
			}

			expr := node.args[0]
			if literal(expr) == literal_no {
				return TypeMap{}, TypeMap{}
			}

			declared := tc.lookup_narrowable_type(expr) or {
				return TypeMap{}, TypeMap{}
			}
			narrowed := tc.resolve_isinstance_target_type(node.args[1]) or {
				return TypeMap{}, TypeMap{}
			}

			key := expr.str()
			mut if_map := TypeMap{}
			if_map[key] = narrow_declared_type(declared, narrowed)
			mut else_map := TypeMap{}
			else_map[key] = remove_type_from_declared_type(declared, narrowed)
			return if_map, else_map
		}
		UnaryExpr {
			if node.op == 'not' {
				if_map, else_map := tc.find_isinstance_check(node.expr)
				return else_map, if_map
			}
		}
		else {}
	}
	return TypeMap{}, TypeMap{}
}

// is_isinstance_call checks whether a call targets builtins.isinstance.
fn (tc TypeChecker) is_isinstance_call(node CallExpr) bool {
	return match node.callee {
		NameExpr {
			is_isinstance_name(node.callee.name, node.callee.fullname)
		}
		MemberExpr {
			is_isinstance_name(node.callee.name, node.callee.fullname)
		}
		else {
			false
		}
	}
}

// lookup_narrowable_type gets the current type of an expression that can be narrowed.
fn (tc TypeChecker) lookup_narrowable_type(expr Expression) ?MypyTypeNode {
	if typ := tc.lookup_type_or_none(expr) {
		return typ
	}

	return match expr {
		NameExpr {
			lookup_symbol_declared_type(expr.node)
		}
		MemberExpr {
			lookup_symbol_declared_type(expr.node)
		}
		else {
			none
		}
	}
}

// resolve_isinstance_target_type resolves the target type in isinstance(expr, target).
fn (tc TypeChecker) resolve_isinstance_target_type(expr Expression) ?MypyTypeNode {
	match expr {
		NameExpr {
			return tc.resolve_isinstance_target_symbol(expr.node, Expression(expr))
		}
		MemberExpr {
			return tc.resolve_isinstance_target_symbol(expr.node, Expression(expr))
		}
		TupleExpr {
			mut items := []MypyTypeNode{}
			for item in expr.items {
				resolved := tc.resolve_isinstance_target_type(item) or {
					return none
				}
				items << resolved
			}
			if items.len == 0 {
				return none
			}
			if items.len == 1 {
				return items[0]
			}
			return make_simplified_union(items, false)
		}
		else {}
	}

	if typ := tc.lookup_type_or_none(expr) {
		proper := get_proper_type(typ)
		if proper is TypeType {
			return proper.item
		}
	}
	return none
}

// is_isinstance_name checks whether a resolved callee name is isinstance.
fn is_isinstance_name(name string, fullname string) bool {
	return name == 'isinstance' || fullname == 'builtins.isinstance'
}

// lookup_symbol_declared_type gets a declared type directly from a symbol node.
fn lookup_symbol_declared_type(sym ?MypyNode) ?MypyTypeNode {
	if node := sym {
		match node {
			Var {
				if typ := node.type_ {
					return typ
				}
			}
			else {}
		}
	}
	return none
}

// resolve_isinstance_target_symbol resolves a narrowable type from a symbol reference.
fn (tc TypeChecker) resolve_isinstance_target_symbol(sym ?MypyNode, expr Expression) ?MypyTypeNode {
	if node := sym {
		match node {
			TypeInfo {
				return MypyTypeNode(instance_from_type_info(node))
			}
			TypeAlias {
				return node.target
			}
			Var {
				if typ := node.type_ {
					proper := get_proper_type(typ)
					if proper is TypeType {
						return proper.item
					} else {
						return typ
					}
				}
			}
			else {}
		}
	}

	if typ := tc.lookup_type_or_none(expr) {
		proper := get_proper_type(typ)
		if proper is TypeType {
			return proper.item
		}
	}
	return none
}

// instance_from_type_info wraps a TypeInfo in an Instance for narrowing checks.
fn instance_from_type_info(info TypeInfo) Instance {
	info_ptr := &TypeInfo{
		base:          info.base
		name:          info.name
		fullname:      info.fullname
		module_name:   info.module_name
		is_abstract:   info.is_abstract
		is_protocol:   info.is_protocol
		is_named_tuple: info.is_named_tuple
		is_enum:       info.is_enum
		is_newtype:    info.is_newtype
		is_dataclass:  info.is_dataclass
		names:         info.names
		mro:           info.mro.clone()
		type_vars:     info.type_vars.clone()
		bases:         info.bases.clone()
		promote_types: info.promote_types.clone()
	}
	return Instance{
		typ:           info_ptr
		type_:         info_ptr
		type_name:     info.fullname
		type_fullname: info.fullname
	}
}

// remove_type_from_declared_type removes known subtypes from a declared type.
fn remove_type_from_declared_type(declared MypyTypeNode, removed MypyTypeNode) MypyTypeNode {
	declared_proper := get_proper_type(declared)
	removed_proper := get_proper_type(removed)

	if removed_proper is UnionType {
		mut current := declared
		for item in removed_proper.items {
			current = remove_type_from_declared_type(current, item)
			if get_proper_type(current) is UninhabitedType {
				return current
			}
		}
		return current
	}

	if declared_proper is UnionType {
		mut remaining := []MypyTypeNode{}
		for item in declared_proper.items {
			if !is_subtype_simple(get_proper_type(item), removed_proper) {
				remaining << item
			}
		}
		if remaining.len == 0 {
			return MypyTypeNode(UninhabitedType{})
		}
		if remaining.len == 1 {
			return remaining[0]
		}
		return make_simplified_union(remaining, false)
	}

	if is_subtype_simple(declared_proper, removed_proper) {
		return MypyTypeNode(UninhabitedType{})
	}
	return declared
}

// push_type_map adds type map
pub fn (mut tc TypeChecker) push_type_map(type_map TypeMap) {
	if tc.is_unreachable_map(type_map) {
		tc.binder.unreachable()
	} else {
		for expr, typ in type_map {
			tc.binder.put(expr, typ, false)
		}
	}
}

// is_unreachable_map checks if map contains UninhabitedType
fn (tc TypeChecker) is_unreachable_map(type_map TypeMap) bool {
	for _, v in type_map {
		if v is UninhabitedType {
			return true
		}
	}
	return false
}

// check_subtype checks subtype
pub fn (mut tc TypeChecker) check_subtype(subtype MypyTypeNode, supertype MypyTypeNode, context Context, msg string) bool {
	if is_subtype(subtype, supertype) {
		return true
	}
	tc.fail(msg, context)
	return false
}

// fail reports an error
pub fn (mut tc TypeChecker) fail(msg string, context Context) {
	tc.msg.fail(msg, context, false, false, none)
}

// note reports an informational message
pub fn (mut tc TypeChecker) note(msg string, context Context) {
	tc.msg.note(msg, context, none)
}

// store_type saves node type
pub fn (mut tc TypeChecker) store_type(node Expression, typ MypyTypeNode) {
	if typ is AnyType && (typ as AnyType).type_of_any == .from_error {
		return
	}
	ctx := node.get_context()
	pkey := '${ctx.line}:${ctx.column}:${node.str()}'
	tc.persistent_type_map[pkey] = typ
}

pub fn (tc &TypeChecker) lookup_persistent_type(node Expression) ?MypyTypeNode {
	ctx := node.get_context()
	pkey := '${ctx.line}:${ctx.column}:${node.str()}'
	return tc.persistent_type_map[pkey] or { none }
}

// has_type checks if node has a type
pub fn (tc TypeChecker) has_type(node Expression) bool {
	key := node.str()
	for m in tc.type_maps {
		if key in m {
			return true
		}
	}
	return false
}

// lookup_type looks up node type
pub fn (tc TypeChecker) lookup_type(node Expression) MypyTypeNode {
	key := node.str()
	for i := tc.type_maps.len - 1; i >= 0; i-- {
		m := tc.type_maps[i]
		if typ := m[key] {
			return typ
		}
	}
	panic('Type not found for node')
}

// lookup_type_or_none looks up node type or returns none
pub fn (tc TypeChecker) lookup_type_or_none(node Expression) ?MypyTypeNode {
	key := node.str()
	for i := tc.type_maps.len - 1; i >= 0; i-- {
		m := tc.type_maps[i]
		if typ := m[key] {
			return typ
		}
	}

	// Fallback for built-in constants if not in local maps
	if key == 'True' || key == 'False' {
		return MypyTypeNode(tc.named_type('bool'))
	} else if key == 'None' {
		return MypyTypeNode(tc.named_type('NoneType'))
	}

	return none
}

// named_type returns Instance with given name
pub fn (tc TypeChecker) named_type(name string) Instance {
	return Instance{
		typ:       none
		type_:     none
		args:      []MypyTypeNode{}
		type_name: name
	}
}

// named_generic_type returns Instance with arguments
pub fn (tc TypeChecker) named_generic_type(name string, args []MypyTypeNode) Instance {
	return Instance{
		typ:       none
		type_:     none
		args:      args
		type_name: name
	}
}

// lookup_typeinfo looks up TypeInfo
fn (tc TypeChecker) lookup_typeinfo(fullname string) TypeInfo {
	_ = tc
	return TypeInfo{
		fullname: fullname
	}
}

// lookup looks up symbol
pub fn (tc TypeChecker) lookup(name string) SymbolTableNode {
	_ = tc
	_ = name
	return SymbolTableNode{}
}

// lookup_qualified looks up qualified name
pub fn (tc TypeChecker) lookup_qualified(name string) SymbolTableNode {
	_ = tc
	_ = name
	return SymbolTableNode{}
}

// type_type returns type 'type'
pub fn (tc TypeChecker) type_type() Instance {
	return tc.named_type('builtins.type')
}

// function_type returns function type
pub fn (tc TypeChecker) function_type(func FuncDef) MypyTypeNode {
	return function_type(func, tc.named_type('builtins.function'))
}

// Helper stub functions
fn is_subtype_stub(left MypyTypeNode, right MypyTypeNode) bool {
	return true
}

fn function_type(func FuncDef, fallback Instance) MypyTypeNode {
	_ = func
	fallback_ptr := &Instance{
		typ:       fallback.typ
		type_:     fallback.type_
		args:      fallback.args.clone()
		type_name: fallback.type_name
	}
	return CallableType{
		arg_types: []MypyTypeNode{}
		arg_kinds: []ArgKind{}
		arg_names: []string{}
		ret_type:  MypyTypeNode(AnyType{
			type_of_any: .from_error
		})
		fallback:  fallback_ptr
	}
}

// ---------------------------------------------------------------------------
// Missing ExpressionVisitor methods for NodeVisitor interface
// ---------------------------------------------------------------------------
pub fn (mut tc TypeChecker) visit_int_expr(mut o IntExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_str_expr(mut o StrExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_bytes_expr(mut o BytesExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_float_expr(mut o FloatExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_complex_expr(mut o ComplexExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_ellipsis(mut o EllipsisExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_star_expr(mut o StarExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_name_expr(mut o NameExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_member_expr(mut o MemberExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_yield_from_expr(mut o YieldFromExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_yield_expr(mut o YieldExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_call_expr(mut o CallExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_op_expr(mut o OpExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_comparison_expr(mut o ComparisonExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_cast_expr(mut o CastExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_assert_type_expr(mut o AssertTypeExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_reveal_expr(mut o RevealExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_super_expr(mut o SuperExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_unary_expr(mut o UnaryExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_assignment_expr(mut o AssignmentExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_list_expr(mut o ListExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_dict_expr(mut o DictExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_template_str_expr(mut o TemplateStrExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_tuple_expr(mut o TupleExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_set_expr(mut o SetExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_index_expr(mut o IndexExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_application(mut o TypeApplication) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_lambda_expr(mut o LambdaExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_list_comprehension(mut o ListComprehension) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_set_comprehension(mut o SetComprehension) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_dictionary_comprehension(mut o DictionaryComprehension) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_generator_expr(mut o GeneratorExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_slice_expr(mut o SliceExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_conditional_expr(mut o ConditionalExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_var_expr(mut o TypeVarExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_paramspec_expr(mut o ParamSpecExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_var_tuple_expr(mut o TypeVarTupleExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_alias_expr(mut o TypeAliasExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_namedtuple_expr(mut o NamedTupleExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_enum_call_expr(mut o EnumCallExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_typeddict_expr(mut o TypedDictExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_newtype_expr(mut o NewTypeExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_promote_expr(mut o PromoteExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_await_expr(mut o AwaitExpr) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_temp_node(mut o TempNode) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_with_stmt(mut o WithStmt) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_del_stmt(mut o DelStmt) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_overloaded_func_def(mut o OverloadedFuncDef) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_global_decl(mut o GlobalDecl) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_nonlocal_decl(mut o NonlocalDecl) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_import(mut o Import) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_import_from(mut o ImportFrom) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_import_all(mut o ImportAll) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_operator_assignment_stmt(mut o OperatorAssignmentStmt) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_assert_stmt(mut o AssertStmt) !AnyNode {
	mut skip_expr_check := false
	match o.expr {
		CallExpr {
			skip_expr_check = tc.is_isinstance_call(o.expr)
		}
		UnaryExpr {
			skip_expr_check = o.expr.op == 'not' && o.expr.expr is CallExpr
				&& tc.is_isinstance_call(o.expr.expr as CallExpr)
		}
		else {}
	}
	if !skip_expr_check {
		tc.expr_checker.accept(o.expr)
	}
	type_map, _ := tc.find_isinstance_check(o.expr)
	tc.push_type_map(type_map)
	if msg := o.msg {
		tc.expr_checker.accept(msg)
	}
	return ''
}

pub fn (mut tc TypeChecker) visit_raise_stmt(mut o RaiseStmt) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_alias_stmt(mut o TypeAliasStmt) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_match_stmt(mut o MatchStmt) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_mypy_file(mut o MypyFile) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_var(mut o Var) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_alias(mut o TypeAlias) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_placeholder_node(mut o PlaceholderNode) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_as_pattern(mut o AsPattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_or_pattern(mut o OrPattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_value_pattern(mut o ValuePattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_singleton_pattern(mut o SingletonPattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_sequence_pattern(mut o SequencePattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_starred_pattern(mut o StarredPattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_mapping_pattern(mut o MappingPattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_class_pattern(mut o ClassPattern) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_argument(mut o Argument) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_param(mut o TypeParam) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_type_info(mut o TypeInfo) !AnyNode {
	return ''
}

pub fn (mut tc TypeChecker) visit_lvalue(mut o Lvalue) !AnyNode {
	match mut o {
		MemberExpr { tc.visit_member_expr(mut o)! }
		NameExpr { tc.visit_name_expr(mut o)! }
		StarExpr { tc.visit_star_expr(mut o)! }
		IndexExpr { tc.visit_index_expr(mut o)! }
		TupleExpr {}
		ListExpr {}
	}
	return ''
}

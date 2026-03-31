module analyzer

import ast
import json
import mypy

pub struct MypyCollectedMutability {
pub mut:
	is_reassigned bool
	is_final      bool
	is_mutated    bool
}

pub struct MypyPluginStore {
pub mut:
	collected_types      map[string]map[string]string
	collected_sigs       map[string]map[string]string
	collected_mutability map[string]map[string]MypyCollectedMutability
	processed_files      map[string]bool
}

pub fn new_mypy_plugin_store() MypyPluginStore {
	return MypyPluginStore{
		collected_types:      map[string]map[string]string{}
		collected_sigs:       map[string]map[string]string{}
		collected_mutability: map[string]map[string]MypyCollectedMutability{}
		processed_files:      map[string]bool{}
	}
}

pub fn (mut s MypyPluginStore) collect_type(name string, loc string, typ string) {
	if name.len == 0 || loc.len == 0 || typ.len == 0 {
		return
	}
	if name !in s.collected_types {
		s.collected_types[name] = map[string]string{}
	}
	s.collected_types[name][loc] = typ
	if '@' !in s.collected_types {
		s.collected_types['@'] = map[string]string{}
	}
	s.collected_types['@'][loc] = typ
	s.collected_types['${name}@${loc}'] = {'${loc}': typ}
}

pub fn (mut s MypyPluginStore) collect_signature(name string, loc string, sig map[string]string) {
	if name.len == 0 || loc.len == 0 {
		return
	}
	encoded := json.encode(sig)
	if name !in s.collected_sigs {
		s.collected_sigs[name] = map[string]string{}
	}
	s.collected_sigs[name][loc] = encoded
	if loc !in s.collected_sigs {
		s.collected_sigs[loc] = map[string]string{}
	}
	s.collected_sigs[loc][loc] = encoded
}

pub fn (mut s MypyPluginStore) collect_mutability(name string, loc string, info MypyCollectedMutability) {
	if name.len == 0 || loc.len == 0 {
		return
	}
	if name !in s.collected_mutability {
		s.collected_mutability[name] = map[string]MypyCollectedMutability{}
	}
	s.collected_mutability[name][loc] = info
}

pub struct MypyPluginAnalyzer {
pub mut:
	store            MypyPluginStore
	mutating_methods []string
	visited          map[string]bool
	checker          ?&mypy.TypeChecker
}

pub fn new_mypy_plugin_analyzer() MypyPluginAnalyzer {
	return MypyPluginAnalyzer{
		store:            new_mypy_plugin_store()
		mutating_methods: ['append', 'extend', 'insert', 'pop', 'remove', 'clear', 'update', 'setdefault',
			'delete', 'add', 'discard', 'intersection_update']
		visited:          map[string]bool{}
		checker:          none
	}
}

pub fn (mut a MypyPluginAnalyzer) collect_file(mut file mypy.MypyFile) {
	a.collect_file_with_checker(mut file, none)
}

pub fn (mut a MypyPluginAnalyzer) collect_file_with_checker(mut file mypy.MypyFile, checker ?&mypy.TypeChecker) {
	file_key := if file.fullpath.len > 0 { file.fullpath } else { file.path }
	if file_key.len > 0 {
		if file_key in a.store.processed_files {
			return
		}
		a.store.processed_files[file_key] = true
	}
	a.checker = checker
	a.visit_mypy_file(mut file)
}

pub fn run_mypy_analysis(source string, filename string) MypyPluginStore {
	mut lexer := ast.new_lexer(source, filename)
	mut parser := ast.new_parser(lexer)
	mod := parser.parse_module()

	mut options := mypy.Options.new()
	mut errors := mypy.new_errors(*options)
	mut api := mypy.new_api(options, &errors)

	mut file := mypy.bridge(mod) or {
		return new_mypy_plugin_store()
	}

	tc := api.check(mut file, map[string]mypy.MypyFile{}) or {
		return new_mypy_plugin_store()
	}

	mut plugin_analyzer := new_mypy_plugin_analyzer()
	plugin_analyzer.collect_file_with_checker(mut file, &tc)
	return plugin_analyzer.store
}

fn bool_string(value bool) string {
	if value {
		return 'true'
	}
	return 'false'
}

fn ctx_key(ctx mypy.Context, tag string) string {
	return '${ctx.line}:${ctx.column}:${tag}'
}

fn (mut a MypyPluginAnalyzer) remember(node_key string) bool {
	if node_key in a.visited {
		return false
	}
	a.visited[node_key] = true
	return true
}

fn (mut a MypyPluginAnalyzer) record_checker_type(expr mypy.Expression) {
	if checker := a.checker {
		if typ := checker.lookup_type_or_none(expr) {
			ctx := expr.get_context()
			key := '${ctx.line}:${ctx.column}'
			a.store.collect_type(expr.str(), key, typ.type_str())
		}
	}
}

fn (mut a MypyPluginAnalyzer) visit_mypy_file(mut file mypy.MypyFile) {
	key := ctx_key(file.get_context(), 'MypyFile:${file.fullname}')
	if !a.remember(key) {
		return
	}
	a.visit_symbol_table(mut file.names)
	for mut stmt in file.defs {
		a.visit_stmt(mut stmt)
	}
}

fn (mut a MypyPluginAnalyzer) visit_symbol_table(mut table mypy.SymbolTable) {
	for _, mut sym in table.symbols {
		if mut node := sym.node {
			mut mn := node.as_mypy_node()
			a.visit_mypy_node(mut mn)
		}
	}
}

fn (mut a MypyPluginAnalyzer) visit_mypy_node(mut node mypy.MypyNode) {
	match mut node {
		mypy.Var { a.visit_var(node) }
		mypy.FuncDef { a.visit_func_def(mut node) }
		mypy.OverloadedFuncDef { a.visit_overloaded_func_def(mut node) }
		mypy.Decorator { a.visit_decorator(mut node) }
		mypy.ClassDef { a.visit_class_def(mut node) }
		mypy.TypeInfo { a.visit_type_info(mut node) }
		mypy.TypeAlias { a.visit_type_alias(node) }
		mypy.MypyFile { a.visit_mypy_file(mut node) }
		mypy.PlaceholderNode {}
		else {}
	}
}

fn (mut a MypyPluginAnalyzer) visit_stmt(mut stmt mypy.Statement) {
	match mut stmt {
		mypy.Block {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_block(mut stmt)
		}
		mypy.ExpressionStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_expr(mut stmt.expr)
		}
		mypy.AssignmentStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_assignment_stmt(mut stmt)
		}
		mypy.OperatorAssignmentStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_operator_assignment_stmt(mut stmt)
		}
		mypy.WhileStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_expr(mut stmt.expr)
			a.visit_block(mut stmt.body)
			if mut else_body := stmt.else_body {
				a.visit_block(mut else_body)
			}
		}
		mypy.ForStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_expr(mut stmt.index)
			a.visit_expr(mut stmt.expr)
			a.visit_block(mut stmt.body)
			if mut else_body := stmt.else_body {
				a.visit_block(mut else_body)
			}
		}
		mypy.IfStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			for mut expr in stmt.expr {
				a.visit_expr(mut expr)
			}
			for mut body in stmt.body {
				a.visit_block(mut body)
			}
			if mut else_body := stmt.else_body {
				a.visit_block(mut else_body)
			}
		}
		mypy.ReturnStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			if mut expr := stmt.expr {
				a.visit_expr(mut expr)
			}
		}
		mypy.AssertStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_expr(mut stmt.expr)
			if mut msg := stmt.msg {
				a.visit_expr(mut msg)
			}
		}
		mypy.RaiseStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			if mut expr := stmt.expr {
				a.visit_expr(mut expr)
			}
			if mut from_expr := stmt.from_node {
				a.visit_expr(mut from_expr)
			}
		}
		mypy.TryStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_block(mut stmt.body)
			for i in 0 .. stmt.handlers.len {
				mut h_body := stmt.handlers[i]
				a.visit_block(mut h_body)
				if mut type_expr := stmt.types[i] {
					a.visit_expr(mut type_expr)
				}
				if target := stmt.vars[i] {
					mut expr_h := target
					a.visit_expr(mut expr_h)
				}
			}
			if mut else_body := stmt.else_body {
				a.visit_block(mut else_body)
			}
			if mut final_body := stmt.finally_body {
				a.visit_block(mut final_body)
			}
		}
		mypy.WithStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			for i in 0 .. stmt.expr.len {
				mut expr := stmt.expr[i]
				a.visit_expr(mut expr)
				if target := stmt.target[i] {
					mut expr_t := target
					a.visit_expr(mut expr_t)
				}
			}
			a.visit_block(mut stmt.body)
		}
		mypy.DelStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_expr(mut stmt.expr)
			a.mark_mutated(stmt.expr)
		}
		mypy.GlobalDecl {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
		mypy.NonlocalDecl {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
		mypy.BreakStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
		mypy.ContinueStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
		mypy.PassStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
		mypy.TypeAliasStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_expr(mut stmt.value)
		}
		mypy.MatchStmt {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_expr(mut stmt.subject)
			for i in 0 .. stmt.bodies.len {
				if mut guard := stmt.guards[i] {
					a.visit_expr(mut guard)
				}
				mut body := stmt.bodies[i]
				a.visit_block(mut body)
			}
		}
		mypy.FuncDef {
			key := ctx_key(stmt.get_context(), typeof(stmt).name + ':' + stmt.fullname)
			if !a.remember(key) { return }
			a.visit_func_def(mut stmt)
		}
		mypy.OverloadedFuncDef {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_overloaded_func_def(mut stmt)
		}
		mypy.Decorator {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
			a.visit_decorator(mut stmt)
		}
		mypy.ClassDef {
			key := ctx_key(stmt.get_context(), typeof(stmt).name + ':' + stmt.fullname)
			if !a.remember(key) { return }
			a.visit_class_def(mut stmt)
		}
		mypy.Import {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
		mypy.ImportFrom {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
		mypy.ImportAll {
			key := ctx_key(stmt.get_context(), typeof(stmt).name)
			if !a.remember(key) { return }
		}
	}
}

fn (mut a MypyPluginAnalyzer) visit_block(mut block mypy.Block) {
	key := ctx_key(block.get_context(), typeof(block).name)
	if !a.remember(key) {
		return
	}
	for mut stmt in block.body {
		a.visit_stmt(mut stmt)
	}
}

fn (mut a MypyPluginAnalyzer) visit_expr(mut expr mypy.Expression) {
	a.record_checker_type(expr)
	match mut expr {
		mypy.NameExpr {
			a.visit_name_expr(mut expr)
		}
		mypy.MemberExpr {
			a.visit_member_expr(mut expr)
		}
		mypy.IndexExpr {
			a.visit_index_expr(mut expr)
		}
		mypy.CallExpr {
			a.visit_call_expr(mut expr)
		}
		mypy.TupleExpr {
			for mut item in expr.items {
				a.visit_expr(mut item)
			}
		}
		mypy.ListExpr {
			for mut item in expr.items {
				a.visit_expr(mut item)
			}
		}
		mypy.DictExpr {
			for mut entry in expr.items {
				if mut key_expr := entry.key {
					a.visit_expr(mut key_expr)
				}
				a.visit_expr(mut entry.value)
			}
		}
		mypy.SetExpr {
			for mut item in expr.items {
				a.visit_expr(mut item)
			}
		}
		mypy.OpExpr {
			a.visit_expr(mut expr.left)
			a.visit_expr(mut expr.right)
		}
		mypy.ComparisonExpr {
			for mut item in expr.operands {
				a.visit_expr(mut item)
			}
		}
		mypy.UnaryExpr {
			a.visit_expr(mut expr.expr)
		}
		mypy.ConditionalExpr {
			a.visit_expr(mut expr.cond)
			a.visit_expr(mut expr.if_expr)
			a.visit_expr(mut expr.else_expr)
		}
		mypy.AssignmentExpr {
			a.visit_expr(mut expr.target)
			a.visit_expr(mut expr.value)
		}
		mypy.LambdaExpr {
			a.visit_expr(mut expr.body)
		}
		mypy.GeneratorExpr {
			a.visit_expr(mut expr.left_expr)
			for mut item in expr.indices {
				a.visit_expr(mut item)
			}
			for mut seq in expr.sequences {
				a.visit_expr(mut seq)
			}
			for mut conds in expr.condlists {
				for mut cond in conds {
					a.visit_expr(mut cond)
				}
			}
		}
		mypy.ListComprehension {
			a.visit_expr(mut expr.generator.left_expr)
		}
		mypy.SetComprehension {
			a.visit_expr(mut expr.generator.left_expr)
		}
		mypy.DictionaryComprehension {
			a.visit_expr(mut expr.key)
			a.visit_expr(mut expr.value)
		}
		mypy.SliceExpr {
			if mut begin := expr.begin {
				a.visit_expr(mut begin)
			}
			if mut end := expr.end {
				a.visit_expr(mut end)
			}
			if mut step := expr.step {
				a.visit_expr(mut step)
			}
		}
		mypy.TemplateStrExpr {}
		mypy.FormatStringExpr {}
		mypy.IntExpr {}
		mypy.StrExpr {}
		mypy.BytesExpr {}
		mypy.FloatExpr {}
		mypy.ComplexExpr {}
		mypy.EllipsisExpr {}
		mypy.StarExpr {
			a.visit_expr(mut expr.expr)
		}
		mypy.TypeApplication {
			a.visit_expr(mut expr.expr)
			for arg in expr.types {
				a.visit_type_node(arg)
			}
		}
		mypy.YieldExpr {
			if mut value := expr.expr {
				a.visit_expr(mut value)
			}
		}
		mypy.YieldFromExpr {
			a.visit_expr(mut expr.expr)
		}
		mypy.AwaitExpr {
			a.visit_expr(mut expr.expr)
		}
		else {}
	}
}

fn (mut a MypyPluginAnalyzer) visit_type_node(typ mypy.MypyTypeNode) {
	key := typ.type_str()
	if key.len == 0 {
		return
	}
	_ = key
}

fn (mut a MypyPluginAnalyzer) visit_name_expr(mut expr mypy.NameExpr) {
	a.mark_name_mutability(expr.name, expr.fullname, expr.get_context(), false, false)
	if mut node := expr.node {
		a.visit_mypy_node(mut node)
	}
}

fn (mut a MypyPluginAnalyzer) visit_member_expr(mut expr mypy.MemberExpr) {
	a.visit_expr(mut expr.expr)
	if mut node := expr.node {
		a.visit_mypy_node(mut node)
	}
}

fn (mut a MypyPluginAnalyzer) visit_index_expr(mut expr mypy.IndexExpr) {
	a.visit_expr(mut expr.base_)
	a.visit_expr(mut expr.index)
}

fn (mut a MypyPluginAnalyzer) visit_call_expr(mut expr mypy.CallExpr) {
	if mut expr.callee is mypy.MemberExpr {
		if expr.callee.name in a.mutating_methods {
			a.mark_mutated(expr.callee.expr)
		}
	}
	a.visit_expr(mut expr.callee)
	for mut arg in expr.args {
		a.visit_expr(mut arg)
	}
}

fn (mut a MypyPluginAnalyzer) visit_var(node mypy.Var) {
	loc := '${node.get_context().line}:${node.get_context().column}'
	if typ := node.type_ {
		a.store.collect_type(node.fullname, loc, typ.type_str())
		if node.name.len > 0 && node.name != node.fullname {
			a.store.collect_type(node.name, loc, typ.type_str())
		}
	}
	mut info := MypyCollectedMutability{
		is_reassigned: false
		is_final: node.is_final
		is_mutated: false
	}
	a.store.collect_mutability(node.fullname, loc, info)
	if node.name.len > 0 && node.name != node.fullname {
		a.store.collect_mutability(node.name, loc, info)
	}
}

fn (mut a MypyPluginAnalyzer) visit_func_def(mut node mypy.FuncDef) {
	key := ctx_key(node.get_context(), 'FuncDef:${node.fullname}')
	if !a.remember(key) {
		return
	}
	loc := '${node.get_context().line}:${node.get_context().column}'
	sig := a.build_function_signature(node)
	a.store.collect_signature(node.fullname, loc, sig)
	if node.name.len > 0 && node.name != node.fullname {
		a.store.collect_signature(node.name, loc, sig)
	}
	if typ := node.type_ {
		a.store.collect_type(node.fullname, loc, typ.type_str())
		if node.name.len > 0 && node.name != node.fullname {
			a.store.collect_type(node.name, loc, typ.type_str())
		}
	}
	for mut arg in node.arguments {
		arg_loc := '${arg.get_context().line}:${arg.get_context().column}'
		mut typ_str := 'Any'
		if typ := arg.type_annotation {
			typ_str = typ.type_str()
		} else if v_typ := arg.variable.type_ {
			typ_str = v_typ.type_str()
		} else {
			continue
		}
		
		a.store.collect_type(arg.variable.fullname, arg_loc, typ_str)
		if arg.variable.name.len > 0 && arg.variable.name != arg.variable.fullname {
			a.store.collect_type(arg.variable.name, arg_loc, typ_str)
		}
	}
	a.visit_block(mut node.body)
}

fn (mut a MypyPluginAnalyzer) visit_overloaded_func_def(mut node mypy.OverloadedFuncDef) {
	loc := '${node.get_context().line}:${node.get_context().column}'
	if typ := node.type_ {
		a.store.collect_type('overload', loc, typ.type_str())
	}
	for mut item in node.items {
		a.visit_func_def(mut item)
	}
}

fn (mut a MypyPluginAnalyzer) visit_decorator(mut node mypy.Decorator) {
	a.visit_func_def(mut node.func)
	if typ := node.var_.type_ {
		loc := '${node.get_context().line}:${node.get_context().column}'
		a.store.collect_type(node.var_.fullname, loc, typ.type_str())
	}
	for mut decorator in node.decorators {
		a.visit_expr(mut decorator)
	}
}

fn (mut a MypyPluginAnalyzer) visit_class_def(mut node mypy.ClassDef) {
	key := ctx_key(node.get_context(), 'ClassDef:${node.fullname}')
	if !a.remember(key) {
		return
	}
	loc := '${node.get_context().line}:${node.get_context().column}'
	sig := a.build_class_signature(node)
	a.store.collect_signature(node.fullname, loc, sig)
	if node.name.len > 0 && node.name != node.fullname {
		a.store.collect_signature(node.name, loc, sig)
	}
	if mut info := node.info {
		a.visit_type_info(mut info)
	}
	for mut base in node.base_type_exprs {
		a.visit_expr(mut base)
	}
	for mut removed in node.removed_base_type_exprs {
		a.visit_expr(mut removed)
	}
	for mut decorator in node.decorators {
		a.visit_expr(mut decorator)
	}
	a.visit_block(mut node.defs)
}

fn (mut a MypyPluginAnalyzer) visit_type_info(mut info mypy.TypeInfo) {
	key := ctx_key(info.get_context(), 'TypeInfo:${info.fullname}')
	if !a.remember(key) {
		return
	}
	loc := '${info.get_context().line}:${info.get_context().column}'
	mut sig := map[string]string{}
	sig['args'] = '[]'
	sig['return'] = info.fullname
	sig['is_class'] = 'true'
	sig['has_init'] = if '__init__' in info.names.symbols { 'true' } else { 'false' }
	sig['has_vararg'] = 'false'
	sig['has_kwarg'] = 'false'
	sig['arg_names'] = '[]'
	sig['defaults'] = '{}'
	a.store.collect_signature(info.fullname, loc, sig)
	if info.name.len > 0 && info.name != info.fullname {
		a.store.collect_signature(info.name, loc, sig)
	}
	a.visit_symbol_table(mut info.names)
}

fn (mut a MypyPluginAnalyzer) visit_type_alias(node mypy.TypeAlias) {
	loc := '${node.get_context().line}:${node.get_context().column}'
	a.store.collect_type(node.fullname, loc, node.target.type_str())
	if node.name.len > 0 && node.name != node.fullname {
		a.store.collect_type(node.name, loc, node.target.type_str())
	}
	for alias_tvar in node.alias_tvars {
		a.visit_type_node(alias_tvar)
	}
}

fn (mut a MypyPluginAnalyzer) visit_assignment_stmt(mut node mypy.AssignmentStmt) {
	loc := '${node.get_context().line}:${node.get_context().column}'
	if typ := node.type_annotation {
		for lvalue in node.lvalues {
			a.collect_annotation_for_lvalue(lvalue, typ, loc)
		}
	}
	for lv in node.lvalues {
		if nested := lv.as_lvalue() {
			mut l := nested
			a.visit_lvalue(mut l, true)
		}
	}
	a.visit_expr(mut node.rvalue)
}

fn (mut a MypyPluginAnalyzer) visit_operator_assignment_stmt(mut node mypy.OperatorAssignmentStmt) {
	a.visit_lvalue(mut node.lvalue, true)
	a.visit_expr(mut node.rvalue)
}

fn (mut a MypyPluginAnalyzer) visit_lvalue(mut lvalue mypy.Lvalue, is_store bool) {
	match mut lvalue {
		mypy.NameExpr {
			a.mark_name_mutability(lvalue.name, lvalue.fullname, lvalue.get_context(), true, false)
			if mut node_ := lvalue.node {
				a.visit_mypy_node(mut node_)
			}
			a.record_checker_type(lvalue)
		}
		mypy.MemberExpr {
			if is_store {
				a.mark_mutated(lvalue.expr)
			}
			a.visit_expr(mut lvalue.expr)
			a.record_checker_type(lvalue)
		}
		mypy.TupleExpr {
			for mut item in lvalue.items {
				if nested := item.as_lvalue() {
					mut l := nested
					a.visit_lvalue(mut l, is_store)
				}
			}
			a.record_checker_type(lvalue)
		}
		mypy.ListExpr {
			for mut item in lvalue.items {
				if nested := item.as_lvalue() {
					mut l := nested
					a.visit_lvalue(mut l, is_store)
				}
			}
			a.record_checker_type(lvalue)
		}
		mypy.StarExpr {
			if nested := lvalue.expr.as_lvalue() {
				mut l := nested
				a.visit_lvalue(mut l, is_store)
			}
			a.record_checker_type(lvalue)
		}
	}
}

fn (mut a MypyPluginAnalyzer) collect_annotation_for_lvalue(lvalue mypy.Expression, typ mypy.MypyTypeNode, loc string) {
	if name_lvalue := lvalue.as_lvalue() {
		match name_lvalue {
			mypy.NameExpr {
				a.store.collect_type(name_lvalue.fullname, loc, typ.type_str())
				if name_lvalue.name.len > 0 && name_lvalue.name != name_lvalue.fullname {
					a.store.collect_type(name_lvalue.name, loc, typ.type_str())
				}
			}
			mypy.TupleExpr {
				for item in name_lvalue.items {
					a.collect_annotation_for_lvalue(item, typ, loc)
				}
			}
			mypy.ListExpr {
				for item in name_lvalue.items {
					a.collect_annotation_for_lvalue(item, typ, loc)
				}
			}
			mypy.StarExpr {
				a.collect_annotation_for_lvalue(name_lvalue.expr, typ, loc)
			}
			else {}
		}
	}
}

fn (mut a MypyPluginAnalyzer) mark_name_mutability(name string, fullname string, ctx mypy.Context, is_reassigned bool, is_mutated bool) {
	if name.len == 0 && fullname.len == 0 {
		return
	}
	loc := '${ctx.line}:${ctx.column}'
	key := if fullname.len > 0 { fullname } else { name }
	mut info := a.store.collected_mutability[key][loc] or {
		MypyCollectedMutability{
			is_reassigned: false
			is_final:      false
			is_mutated:    false
		}
	}
	info.is_reassigned = info.is_reassigned || is_reassigned
	info.is_mutated = info.is_mutated || is_mutated
	a.store.collect_mutability(key, loc, info)
	if fullname.len > 0 && fullname != name {
		a.store.collect_mutability(name, loc, info)
	}
}

fn (mut a MypyPluginAnalyzer) mark_mutated(expr mypy.Expression) {
	match expr {
		mypy.NameExpr {
			a.mark_name_mutability(expr.name, expr.fullname, expr.get_context(), false, true)
		}
		mypy.MemberExpr {
			a.mark_mutated(expr.expr)
		}
		mypy.TupleExpr {
			for item in expr.items {
				a.mark_mutated(item)
			}
		}
		mypy.ListExpr {
			for item in expr.items {
				a.mark_mutated(item)
			}
		}
		else {}
	}
}

fn (a &MypyPluginAnalyzer) build_function_signature(node mypy.FuncDef) map[string]string {
	mut args := []string{}
	mut callable_args := []string{}
	if typ := node.type_ {
		if typ is mypy.CallableType {
			c_typ := typ as mypy.CallableType
			for at in c_typ.arg_types {
				callable_args << at.type_str()
			}
		}
	}
	
	mut arg_names := []string{}
	mut defaults := map[string]string{}
	for i, arg in node.arguments {
		arg_names << arg.variable.name
		if i < callable_args.len {
			args << callable_args[i]
		} else if typ := arg.type_annotation {
			args << typ.type_str()
		} else if var_typ := arg.variable.type_ {
			args << var_typ.type_str()
		} else {
			args << 'Any'
		}
		if arg.initializer != none {
			defaults[arg.variable.name] = 'default'
		}
	}
	ret_type := if typ := node.type_ {
		if typ is mypy.CallableType {
			typ.ret_type.type_str()
		} else {
			typ.type_str()
		}
	} else {
		'Any'
	}
	return {
		'args':       json.encode(args)
		'return':     ret_type
		'is_class':   bool_string(node.is_class)
		'has_init':   'false'
		'has_vararg': bool_string(false)
		'has_kwarg':  bool_string(false)
		'arg_names':  json.encode(arg_names)
		'defaults':   json.encode(defaults)
	}
}

fn (a &MypyPluginAnalyzer) build_class_signature(node mypy.ClassDef) map[string]string {
	mut has_init := false
	if info := node.info {
		has_init = '__init__' in info.names.symbols
	}
	return {
		'args':       '[]'
		'return':     node.fullname
		'is_class':   'true'
		'has_init':   bool_string(has_init)
		'has_vararg': 'false'
		'has_kwarg':  'false'
		'arg_names':  '[]'
		'defaults':   '{}'
	}
}

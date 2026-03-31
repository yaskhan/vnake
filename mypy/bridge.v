// I, Antigravity, am working on this file. Started: 2026-03-31 19:35
module mypy

import ast

// bridge converts V's ast.Module (native parser) to Mypy's MypyFile (semantic nodes).
pub fn bridge(v_mod ast.Module) !MypyFile {
	mut defs := []Statement{}

	for stmt in v_mod.body {
		if s := convert_statement(stmt) {
			defs << s
		}
	}

	return MypyFile{
		fullname: v_mod.filename
		path:     v_mod.filename
		names:    SymbolTable{symbols: map[string]SymbolTableNode{}}
		defs:     defs
	}
}

fn convert_context(tok ast.Token) Context {
	return Context{
		line:   tok.line
		column: tok.column
	}
}

fn convert_block(stmts []ast.Statement) Block {
	mut nodes := []Statement{}
	for s in stmts {
		if node := convert_statement(s) {
			nodes << node
		}
	}
	ctx := if stmts.len > 0 { convert_context(stmts[0].get_token()) } else { Context{} }
	return Block{
		body: nodes
		base: NodeBase{ctx: ctx}
	}
}

fn convert_arguments(args ast.Arguments) ([]Argument, []string, []ArgKind) {
	mut res_args := []Argument{}
	mut res_names := []string{}
	mut res_kinds := []ArgKind{}

	// posonlyargs
	for arg in args.posonlyargs {
		res_args << Argument{
			variable: Var{name: arg.arg, fullname: arg.arg, base: NodeBase{ctx: convert_context(arg.token)}}
			kind: .arg_pos
			pos_only: true
			base: NodeBase{ctx: convert_context(arg.token)}
		}
		res_names << arg.arg
		res_kinds << .arg_pos
	}

	// regular args
	for arg in args.args {
		kind := if arg.default_ == none { ArgKind.arg_pos } else { ArgKind.arg_opt }
		res_args << Argument{
			variable: Var{name: arg.arg, fullname: arg.arg, base: NodeBase{ctx: convert_context(arg.token)}}
			kind: kind
			base: NodeBase{ctx: convert_context(arg.token)}
		}
		res_names << arg.arg
		res_kinds << kind
	}

	// vararg
	if va := args.vararg {
		res_args << Argument{
			variable: Var{name: va.arg, fullname: va.arg, base: NodeBase{ctx: convert_context(va.token)}}
			kind: .arg_star
			base: NodeBase{ctx: convert_context(va.token)}
		}
		res_names << va.arg
		res_kinds << .arg_star
	}

	// kwonlyargs
	for arg in args.kwonlyargs {
		kind := if arg.default_ == none { ArgKind.arg_named } else { ArgKind.arg_named_opt }
		res_args << Argument{
			variable: Var{name: arg.arg, fullname: arg.arg, base: NodeBase{ctx: convert_context(arg.token)}}
			kind: kind
			base: NodeBase{ctx: convert_context(arg.token)}
		}
		res_names << arg.arg
		res_kinds << kind
	}

	// kwarg
	if ka := args.kwarg {
		res_args << Argument{
			variable: Var{name: ka.arg, fullname: ka.arg, base: NodeBase{ctx: convert_context(ka.token)}}
			kind: .arg_star2
			base: NodeBase{ctx: convert_context(ka.token)}
		}
		res_names << ka.arg
		res_kinds << .arg_star2
	}

	return res_args, res_names, res_kinds
}

fn convert_statement(stmt ast.Statement) ?Statement {
	ctx := convert_context(stmt.get_token())
	match stmt {
		ast.FunctionDef {
			args, names, kinds := convert_arguments(stmt.args)
			func_def := FuncDef{
				name: stmt.name
				base: NodeBase{ctx: ctx}
				body: convert_block(stmt.body)
				arguments: args
				arg_names: names
				arg_kinds: kinds
			}
			return Statement(func_def)
		}
		ast.ClassDef {
			class_def := ClassDef{
				name: stmt.name
				base: NodeBase{ctx: ctx}
				defs: convert_block(stmt.body)
				// TODO: bases
			}
			return Statement(class_def)
		}
		ast.Assign {
			mut rvalue := convert_expression(stmt.value) or { return none }
			mut lvalues := []Expression{}
			for t in stmt.targets {
				if expr := convert_expression(t) {
					lvalues << expr
				}
			}
			assign_stmt := AssignmentStmt{
				lvalues: lvalues
				rvalue:  rvalue
				base:    NodeBase{ctx: ctx}
			}
			return Statement(assign_stmt)
		}
		ast.Return {
			mut value := ?Expression(none)
			if v := stmt.value {
				value = convert_expression(v)
			}
			return_stmt := ReturnStmt{
				expr: value
				base:  NodeBase{ctx: ctx}
			}
			return Statement(return_stmt)
		}
		ast.If {
			mut else_stmt := ?Block(none)
			if stmt.orelse.len > 0 {
				else_stmt = convert_block(stmt.orelse)
			}
			if_stmt := IfStmt{
				expr: [convert_expression(stmt.test) or { return none }]
				body: [convert_block(stmt.body)]
				else_body: else_stmt
				base: NodeBase{ctx: ctx}
			}
			return Statement(if_stmt)
		}
		ast.While {
			while_stmt := WhileStmt{
				expr: convert_expression(stmt.test) or { return none }
				body: convert_block(stmt.body)
				else_body: if stmt.orelse.len > 0 { convert_block(stmt.orelse) } else { none }
				base: NodeBase{ctx: ctx}
			}
			return Statement(while_stmt)
		}
		ast.For {
			for_stmt := ForStmt{
				index: convert_expression(stmt.target) or { return none }
				expr:  convert_expression(stmt.iter) or { return none }
				body:  convert_block(stmt.body)
				else_body: if stmt.orelse.len > 0 { convert_block(stmt.orelse) } else { none }
				base: NodeBase{ctx: ctx}
			}
			return Statement(for_stmt)
		}
		ast.Try {
			mut handlers := []Block{}
			mut types := []?Expression{}
			mut vars := []?NameExpr{}
			for handler in stmt.handlers {
				handlers << convert_block(handler.body)
				types << if t := handler.typ { convert_expression(t) } else { none }
				vars << if v := handler.name { 
					?NameExpr(NameExpr{
						name: v
						base: NodeBase{ctx: convert_context(handler.token)}
					})
				} else { none }
			}
			try_stmt := TryStmt{
				body: convert_block(stmt.body)
				handlers: handlers
				types: types
				vars: vars
				else_body: if stmt.orelse.len > 0 { convert_block(stmt.orelse) } else { none }
				finally_body: if stmt.finalbody.len > 0 { convert_block(stmt.finalbody) } else { none }
				base: NodeBase{ctx: ctx}
			}
			return Statement(try_stmt)
		}
		ast.With {
			mut items := []Expression{}
			mut targets := []?Expression{}
			for item in stmt.items {
				items << convert_expression(item.context_expr) or { continue }
				targets << if t := item.optional_vars { convert_expression(t) } else { none }
			}
			with_stmt := WithStmt{
				expr: items
				target: targets
				body: convert_block(stmt.body)
				base: NodeBase{ctx: ctx}
			}
			return Statement(with_stmt)
		}
		ast.Expr {
			if expr := convert_expression(stmt.value) {
				expr_stmt := ExpressionStmt{
					expr: expr
					base: NodeBase{ctx: ctx}
				}
				return Statement(expr_stmt)
			}
			return none
		}
		ast.Import {
			mut ids := []ImportAlias{}
			for alias in stmt.names {
				ids << ImportAlias{name: alias.name, alias: alias.asname}
			}
			import_stmt := Import{
				base: NodeBase{ctx: ctx}
				ids: ids
			}
			return Statement(import_stmt)
		}
		ast.ImportFrom {
			mut names := []ImportAlias{}
			for alias in stmt.names {
				names << ImportAlias{name: alias.name, alias: alias.asname}
			}
			import_from_stmt := ImportFrom{
				base: NodeBase{ctx: ctx}
				id: stmt.module
				relative: stmt.level
				names: names
			}
			return Statement(import_from_stmt)
		}
		ast.Assert {
			assert_stmt := AssertStmt{
				base: NodeBase{ctx: ctx}
				expr: convert_expression(stmt.test) or { return none }
				msg: if m := stmt.msg { convert_expression(m) } else { none }
			}
			return Statement(assert_stmt)
		}
		ast.Pass {
			pass_stmt := PassStmt{
				base: NodeBase{ctx: ctx}
			}
			return Statement(pass_stmt)
		}
		ast.Break {
			break_stmt := BreakStmt{
				base: NodeBase{ctx: ctx}
			}
			return Statement(break_stmt)
		}
		ast.Continue {
			continue_stmt := ContinueStmt{
				base: NodeBase{ctx: ctx}
			}
			return Statement(continue_stmt)
		}
		else {
			return none
		}
	}
}

fn convert_expression(expr ast.Expression) ?Expression {
	ctx := convert_context(expr.get_token())
	match expr {
		ast.Name {
			return Expression(NameExpr{
				name: expr.id
				base: NodeBase{ctx: ctx}
			})
		}
		ast.Constant {
			// Try to infer type from value string or token
			if expr.token.typ == .number {
				if expr.value.contains('.') {
					return Expression(FloatExpr{
						value: expr.value.f64()
						base:  NodeBase{ctx: ctx}
					})
				}
				return Expression(IntExpr{
					value: expr.value.i64()
					base:  NodeBase{ctx: ctx}
				})
			}
			return Expression(StrExpr{
				value: expr.value
				base:  NodeBase{ctx: ctx}
			})
		}
		ast.Attribute {
			if val := convert_expression(expr.value) {
				return Expression(MemberExpr{
					expr: val
					name: expr.attr
					base: NodeBase{ctx: ctx}
				})
			}
			return none
		}
		ast.Call {
			if func := convert_expression(expr.func) {
				mut args := []Expression{}
				for a in expr.args {
					if ae := convert_expression(a) {
						args << ae
					}
				}
				return Expression(CallExpr{
					callee: func
					args:   args
					base:   NodeBase{ctx: ctx}
				})
			}
			return none
		}
		ast.Subscript {
			if val := convert_expression(expr.value) {
				if idx := convert_expression(expr.slice) {
					return Expression(IndexExpr{
						base:  NodeBase{ctx: ctx}
						index: idx
						base_: val
					})
				}
			}
			return none
		}
		ast.BinaryOp {
			if left := convert_expression(expr.left) {
				if right := convert_expression(expr.right) {
					return Expression(OpExpr{
						op:    expr.op.value
						left:  left
						right: right
						base:  NodeBase{ctx: ctx}
					})
				}
			}
			return none
		}
		ast.UnaryOp {
			if operand := convert_expression(expr.operand) {
				return Expression(UnaryExpr{
					op:    expr.op.value
					expr:  operand
					base:  NodeBase{ctx: ctx}
				})
			}
			return none
		}
		ast.Compare {
			mut opds := []Expression{}
			opds << convert_expression(expr.left) or { return none }
			mut operators := []string{}
			for op in expr.ops { operators << op.value }
			for comp in expr.comparators { opds << convert_expression(comp) or { return none } }
			return Expression(ComparisonExpr{
				operators: operators
				operands:  opds
				base:      NodeBase{ctx: ctx}
			})
		}
		ast.List {
			mut items := []Expression{}
			for i in expr.elements { items << convert_expression(i) or { continue } }
			return Expression(ListExpr{
				items: items
				base:  NodeBase{ctx: ctx}
			})
		}
		ast.Tuple {
			mut items := []Expression{}
			for i in expr.elements { items << convert_expression(i) or { continue } }
			return Expression(TupleExpr{
				items: items
				base:  NodeBase{ctx: ctx}
			})
		}
		ast.Dict {
			mut entries := []DictEntry{}
			for i, key in expr.keys {
				if k := convert_expression(key) {
					if v := convert_expression(expr.values[i]) {
						entries << DictEntry{key: k, value: v}
					}
				}
			}
			return Expression(DictExpr{
				items: entries
				base:  NodeBase{ctx: ctx}
			})
		}
		else {
			return none
		}
	}
}

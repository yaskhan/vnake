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

fn convert_statement(stmt ast.Statement) ?Statement {
	ctx := convert_context(stmt.get_token())
	match stmt {
		ast.FunctionDef {
			return Statement(FuncDef{
				name: stmt.name
				base: NodeBase{ctx: ctx}
				// TODO: body, arguments
			})
		}
		ast.ClassDef {
			return Statement(ClassDef{
				name: stmt.name
				base: NodeBase{ctx: ctx}
				// TODO: body, bases
			})
		}
		ast.Assign {
			mut rvalue := convert_expression(stmt.value) or { return none }
			mut lvalues := []Expression{}
			for t in stmt.targets {
				if expr := convert_expression(t) {
					lvalues << expr
				}
			}
			return Statement(AssignmentStmt{
				lvalues: lvalues
				rvalue:  rvalue
				base:    NodeBase{ctx: ctx}
			})
		}
		ast.Return {
			mut value := ?Expression(none)
			if v := stmt.value {
				value = convert_expression(v)
			}
			return Statement(ReturnStmt{
				expr: value
				base:  NodeBase{ctx: ctx}
			})
		}
		ast.Expr {
			if expr := convert_expression(stmt.value) {
				return Statement(ExpressionStmt{
					expr: expr
					base: NodeBase{ctx: ctx}
				})
			}
			return none
		}
		ast.Import {
			// Minimal bridge for imports
			return Statement(Import{
				base: NodeBase{ctx: ctx}
			})
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
		else {
			return none
		}
	}
}

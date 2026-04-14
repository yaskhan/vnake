module translator

import ast

fn (t &Translator) collect_mutable_locals(stmts []ast.Statement, mut names map[string]bool) {
	for stmt in stmts {
		t.collect_mutable_locals_stmt(stmt, mut names)
	}
}

fn (t &Translator) collect_mutable_locals_stmt(stmt ast.Statement, mut names map[string]bool) {
	match stmt {
		ast.Assign {
			for target in stmt.targets {
				if target is ast.Attribute {
					if target.value is ast.Name {
						names[target.value.id] = true
					}
				} else if target is ast.Name {
					if target.id in names {
						// Already saw it once, so it's mutable if reassigned
						names[target.id] = true
					} else {
						// First time seeing it, might be just initialization
						// But for now, we need a way to track "seen once" vs "reassigned".
						// Given the current map[string]bool, we can't easily distinguish.
						// However, if we assume any local assigned in a loop or IF is potentially mutable?
					}
				}
			}
		}
		ast.AnnAssign {
			if stmt.target is ast.Attribute {
				if stmt.target.value is ast.Name {
					names[stmt.target.value.id] = true
				}
			}
		}
		ast.AugAssign {
			if stmt.target is ast.Attribute {
				if stmt.target.value is ast.Name {
					names[stmt.target.value.id] = true
				}
			}
		}
		ast.Expr {
			if stmt.value is ast.Call {
				if stmt.value.func is ast.Attribute {
					if stmt.value.func.value is ast.Name {
						names[stmt.value.func.value.id] = true
					}
				}
			}
		}
		ast.If {
			t.collect_mutable_locals(stmt.body, mut names)
			t.collect_mutable_locals(stmt.orelse, mut names)
		}
		ast.For {
			t.collect_mutable_locals(stmt.body, mut names)
			t.collect_mutable_locals(stmt.orelse, mut names)
		}
		ast.While {
			t.collect_mutable_locals(stmt.body, mut names)
			t.collect_mutable_locals(stmt.orelse, mut names)
		}
		ast.Try {
			t.collect_mutable_locals(stmt.body, mut names)
			t.collect_mutable_locals(stmt.orelse, mut names)
			t.collect_mutable_locals(stmt.finalbody, mut names)
		}
		ast.With {
			t.collect_mutable_locals(stmt.body, mut names)
		}
		else {}
	}
}

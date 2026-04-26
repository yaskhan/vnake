module base

import ast

// PrecedenceMixin - utilities for operator precedence and parentheses

struct PrecedenceTokenCarrier {
	token ast.Token
}

// precedence_from_operator returns precedence levels for V 0.5.1
fn precedence_from_operator(op string) int {
	return match op {
		'or' { 10 }
		'and' { 20 }
		'not' { 30 }
		'in', 'not in', 'is', 'is not', '==', '!=', '<', '<=', '>', '>=' { 40 }
		'|', '^', '+', '-' { 50 } // V: |, ^ have same precedence as +
		'&', '*', '/', '//', '%' { 60 } // V: & has same precedence as *
		'<<', '>>' { 70 } // V: Shifts have higher precedence than * in some cases, but definitely > +
		'u+', 'u-', '~' { 80 }
		'**' { 90 }
		else { 100 }
	}
}

fn node_operator(node voidptr) string {
	if node == unsafe { nil } {
		return ''
	}
	h := unsafe { &PrecedenceTokenCarrier(node) }
	if h.token.typ == .keyword && h.token.value == 'not' {
		return 'not'
	}
	return h.token.value
}

fn is_commutative_operator(op string) bool {
	return op in ['+', '*', '&', '|', '^', '==', '!=']
}

fn is_right_associative_operator(op string) bool {
	return op == '**'
}

// get_precedence returns precedence for AST nodes.
pub fn get_precedence(node voidptr) int {
	return precedence_from_operator(node_operator(node))
}

// visit_with_parens visits child_node and wraps result into parentheses when needed.
pub fn visit_with_parens(parent_node voidptr, child_node voidptr, is_right_operand bool, visit_fn fn (voidptr) string) string {
	parent_prec := get_precedence(parent_node)
	child_prec := get_precedence(child_node)
	child_str := visit_fn(child_node)
	parent_op := node_operator(parent_node)
	child_op := node_operator(child_node)

	mut needs_parens := false
	if child_prec < parent_prec {
		needs_parens = true
	} else if child_prec == parent_prec && is_right_operand {
		if parent_op != child_op {
			needs_parens = true
		} else {
			needs_parens = !is_commutative_operator(parent_op)
			if is_right_associative_operator(parent_op) && parent_op == child_op {
				needs_parens = false
			}
		}
	}

	if parent_op == '**' && child_op in ['u+', 'u-', '~', 'not', '+', '-'] {
		needs_parens = true
	}

	if needs_parens {
		return '(${child_str})'
	}
	return child_str
}

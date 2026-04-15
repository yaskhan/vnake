module analyzer

import regex

pub fn get_mypy_tips(mypy_output string) string {
	if mypy_output.len == 0 {
		return ''
	}

	// Use regex module to match mypy error codes [code]
	mut re := regex.regex_opt(r'\[([a-z-]+)\]') or { return '' }
	matches := re.find_all_str(mypy_output)

	mut found_codes := map[string]bool{}
	for m in matches {
		// Extract code within brackets
		if m.len > 2 {
			code := m[1..m.len - 1]
			found_codes[code] = true
		}
	}

	mut tips := []string{}
	mut sorted_codes := found_codes.keys()
	sorted_codes.sort()

	for code in sorted_codes {
		match code {
			'union-attr' {
				tips << '- [union-attr] In V, you must explicitly check the type (e.g., using `if x is Type`) before accessing a union attribute.'
			}
			'arg-type' {
				tips << '- [arg-type] In V, function arguments are strictly typed. Ensure the passed value matches the expected type or use a sum type.'
			}
			'return-value' {
				tips << '- [return-value] V requires the return value to strictly match the function signature.'
			}
			'assignment' {
				tips << '- [assignment] V is statically typed; ensure the variable type matches the value being assigned. Re-assignments to different types are not allowed.'
			}
			'index' {
				tips << '- [index] V array indices must be integers. Map keys must match the declared key type.'
			}
			'attr-defined' {
				tips << '- [attr-defined] Ensure the struct field or method exists in the V definition. V does not allow dynamic attribute addition.'
			}
			'operator' {
				tips << '- [operator] V is strict about operand types. Ensure both sides of the operator have compatible types.'
			}
			'call-arg' {
				tips << '- [call-arg] V function calls must match the exact number of defined parameters. Optional arguments in Python are often handled via Optionals or default values in V.'
			}
			'name-defined' {
				tips << '- [name-defined] In V, all variables and functions must be declared before use or be visible in the current module scope.'
			}
			'variance' {
				tips << '- [variance] Variance violation detected. Python 3.13+ PEP 695 variance modifiers must be strictly followed in generic definitions.'
			}
			'misc' {
				if mypy_output.contains('TypeForm') {
					tips << "- [misc] Experimental feature 'TypeForm' detected. Use --experimental flag if supported, or simplify the type usage for V compatibility."
				}
			}
			else {}
		}
	}

	if tips.len == 0 {
		return ''
	}

	return '\nV-specific tips for found Mypy errors:\n' + tips.join('\n') + '\n'
}

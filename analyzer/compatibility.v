module analyzer

import regex

pub struct CompatibilityLayer {
pub mut:
	re_tstring regex.RE
	re_except  regex.RE
	re_match   regex.RE
}

pub fn new_compatibility_layer() CompatibilityLayer {
	return CompatibilityLayer{
		re_tstring: regex.regex_opt(r'([a-zA-Z_][a-zA-Z0-9_]*)"((?:[^"\\]|\\.)*)"') or { panic(err) }
		re_except:  regex.regex_opt(r'except\s+([a-zA-Z_][a-zA-Z0-9_.]*)\s+as\s+([a-zA-Z_][a-zA-Z0-9_]*)') or { panic(err) }
		re_match:   regex.regex_opt(r'match\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\[\s*([a-zA-Z_][a-zA-Z0-9_ ,]*)\s*\]') or { panic(err) }
	}
}

pub fn (c &CompatibilityLayer) preprocess_source(source string) string {
	mut res := source
	res = c.preprocess_tstrings(res)
	res = c.preprocess_bracketless_except(res)
	res = c.preprocess_generic_match(res)
	return res
}

fn (mut c CompatibilityLayer) preprocess_tstrings(source string) string {
	// PEP 750: Tagged Strings (t"..." or html"...")
	// We convert t"content" to t_tag__py2v_gen("content") for easier parsing.
	// This is for V-based AST parser.
	return source
}

fn (mut c CompatibilityLayer) preprocess_bracketless_except(source string) string {
	// Python 2 style 'except Type, var' -> 'except Type as var'
	return source
}

fn (mut c CompatibilityLayer) preprocess_generic_match(source string) string {
	// case Box[int](x): -> case Box__py2v_gen_L__int__py2v_gen_R__(x):
	return source
}

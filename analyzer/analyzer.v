module analyzer

import ast

// Analyzer - main structure for Python code analysis
@[heap]
pub struct Analyzer {
	TypeInferenceVisitorMixin
pub mut:
	context               string
	stack                 []string
}

// new_analyzer creates a new Analyzer instance
pub fn new_analyzer(type_data map[string]string) &Analyzer {
	mut a := &Analyzer{
		TypeInferenceVisitorMixin: new_type_inference_visitor_mixin()
		context:                   ''
		stack:                     []string{}
	}
	a.type_map = type_data.clone()
	return a
}

// analyze runs Python code analysis
pub fn (mut a Analyzer) analyze(node ast.Module) {
	a.overloaded_signatures.clear()
	a.visit_module(node)
	
	mut ai := new_alias_inferer()
	ai.analyze(node)
	for k, v in ai.alias_to_type {
		a.type_map[k] = v
	}
	
	mut fms := new_function_mutability_scanner()
	fms.analyze(node, mut a.mutability_map)
	a.func_param_mutability = fms.func_param_mutability.clone()
}

// get_type returns variable type
pub fn (a Analyzer) get_type(name string) ?string {
	if name in a.type_map {
		return a.type_map[name]
	}
	return none
}

// set_type sets variable type
pub fn (mut a Analyzer) set_type(name string, typ string) {
	a.type_map[name] = typ
}

// get_raw_type returns raw type string
pub fn (a Analyzer) get_raw_type(name string) ?string {
	if name in a.raw_type_map {
		return a.raw_type_map[name]
	}
	return none
}

// set_raw_type sets raw type string
pub fn (mut a Analyzer) set_raw_type(name string, typ string) {
	a.raw_type_map[name] = typ
}

// get_mutability returns mutability information
pub fn (a Analyzer) get_mutability(name string) ?MutabilityInfo {
	if name in a.mutability_map {
		return a.mutability_map[name]
	}
	return none
}

// set_mutability sets mutability information
pub fn (mut a Analyzer) set_mutability(name string, info MutabilityInfo) {
	a.mutability_map[name] = info
}

// add_class_to_hierarchy adds class to hierarchy
pub fn (mut a Analyzer) add_class_to_hierarchy(class_name string, bases []string) {
	a.class_hierarchy[class_name] = bases
}

// get_class_bases returns base classes
pub fn (a Analyzer) get_class_bases(class_name string) []string {
	if class_name in a.class_hierarchy {
		return a.class_hierarchy[class_name]
	}
	return []
}

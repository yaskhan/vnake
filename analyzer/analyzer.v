module analyzer

import ast

// Analyzer - main structure for Python code analysis
@[heap]
pub struct Analyzer {
	TypeInferenceVisitorMixin
pub mut:
	mypy_store            MypyPluginStore
	context               string
	stack                 []string
}

// new_analyzer creates a new Analyzer instance
pub fn new_analyzer(type_data map[string]string) &Analyzer {
	mut a := &Analyzer{
		TypeInferenceVisitorMixin: new_type_inference_visitor_mixin()
		mypy_store:                new_mypy_plugin_store()
		context:                   ''
		stack:                     []string{}
	}
	a.analyzer_ptr = a
a.type_map = type_data.clone()
	return a
}

// analyze runs Python code analysis
pub fn (mut a Analyzer) analyze(node ast.Module) {
	a.overloaded_signatures.clear()
	a.visit_module(node)
	
	mut ai := new_alias_inferer()
	ai.analyze(node, mut a.TypeInferenceVisitorMixin.TypeInferenceUtilsMixin)
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

// get_mypy_type returns type from mypy store
pub fn (a Analyzer) get_mypy_type(name string, loc string) ?string {
	if name.len > 0 && loc.len > 0 {
		if res := a.mypy_store.collected_types[name] {
			if typ := res[loc] {
				return typ
			}
		}
	}
	if loc.len > 0 {
		if res := a.mypy_store.collected_types['@'] {
			if typ := res[loc] {
				return typ
			}
		}
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
// load_mypy_data loads data from MypyPluginStore
pub fn (mut a Analyzer) load_mypy_data(store MypyPluginStore) {
	for k, v in store.collected_types {
		if k !in a.mypy_store.collected_types {
			a.mypy_store.collected_types[k] = map[string]string{}
		}
		for loc, typ in v {
			a.mypy_store.collected_types[k][loc] = typ
		}
	}
	for k, v in store.collected_sigs {
		if k !in a.mypy_store.collected_sigs {
			a.mypy_store.collected_sigs[k] = map[string]string{}
		}
		for loc, sig in v {
			a.mypy_store.collected_sigs[k][loc] = sig
		}
	}
}

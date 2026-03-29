module analyzer

import ast

pub struct PydanticDetector {}

pub fn (d PydanticDetector) is_pydantic_model(node ast.ClassDef) bool {
	for base in node.bases {
		if base is ast.Name {
			if base.id == 'BaseModel' {
				return true
			}
		}
		if base is ast.Attribute {
			if base.attr == 'BaseModel' {
				val := base.value
				if val is ast.Name {
					if val.id == 'pydantic' {
						return true
					}
				}
			}
		}
		if base is ast.Subscript {
			val := base.value
			if val is ast.Name && val.id == 'BaseModel' {
				return true
			}
			if val is ast.Attribute && val.attr == 'BaseModel' {
				inner_val := val.value
				if inner_val is ast.Name && inner_val.id == 'pydantic' {
					return true
				}
			}
		}
	}
	return false
}

pub fn (d PydanticDetector) is_pydantic_field(node ast.Expression) bool {
	if node is ast.Call {
		func := node.func
		if func is ast.Name && func.id == 'Field' {
			return true
		}
		if func is ast.Attribute && func.attr == 'Field' {
			val := func.value
			if val is ast.Name && val.id == 'pydantic' {
				return true
			}
		}
	}
	return false
}

pub fn (d PydanticDetector) is_validator_decorator(node ast.Expression) bool {
	match node {
		ast.Name {
			return node.id in ['validator', 'field_validator', 'model_validator']
		}
		ast.Call {
			func := node.func
			if func is ast.Name {
				return func.id in ['validator', 'field_validator', 'model_validator']
			}
		}
		ast.Attribute {
			return node.attr in ['validator', 'field_validator', 'model_validator']
		}
		else {
			return false
		}
	}
	return false
}

pub fn (d PydanticDetector) is_computed_field(node ast.Expression) bool {
	match node {
		ast.Name {
			return node.id == 'computed_field'
		}
		ast.Attribute {
			return node.attr == 'computed_field'
		}
		ast.Call {
			func := node.func
			if func is ast.Name {
				return func.id == 'computed_field'
			}
			if func is ast.Attribute {
				return func.attr == 'computed_field'
			}
		}
		else {
			return false
		}
	}
	return false
}

pub fn (d PydanticDetector) is_config_dict(node ast.Expression) bool {
	if node is ast.Call {
		func := node.func
		if func is ast.Name && func.id == 'ConfigDict' {
			return true
		}
		if func is ast.Attribute && func.attr == 'ConfigDict' {
			return true
		}
	}
	return false
}

pub fn (d PydanticDetector) is_config_class(node ast.Statement) bool {
	if node is ast.ClassDef {
		return node.name == 'Config'
	}
	return false
}

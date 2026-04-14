module classes

import ast

pub struct FieldDefInfo {
pub mut:
	name        string
	orig_name   string
	def         string
	is_mutated  bool
	is_readonly bool
}

pub struct ClassFieldsHandler {}

fn (h ClassFieldsHandler) normalize_field_type(field_type string) string {
	if field_type == 'none' {
		return 'Any'
	}
	return field_type
}

fn (h ClassFieldsHandler) field_usage_parts(v_type string) []string {
	mut parts := []string{}
	if v_type.len == 0 || v_type in ['Any', 'unknown'] {
		return parts
	}
	for raw_part in v_type.split(' | ') {
		part := raw_part.trim_space()
		if part.len == 0 || part in ['Any', 'unknown'] {
			continue
		}
		if part.starts_with('?') {
			inner := part[1..]
			if inner.len > 0 && inner !in parts {
				parts << inner
			}
			if 'none' !in parts {
				parts << 'none'
			}
			continue
		}
		if part !in parts {
			parts << part
		}
	}
	return parts
}

fn (h ClassFieldsHandler) merge_inferred_field_types(existing string, candidate string) string {
	mut parts := h.field_usage_parts(existing)
	for part in h.field_usage_parts(candidate) {
		if part !in parts {
			parts << part
		}
	}
	if parts.len == 0 {
		return 'Any'
	}
	has_none := 'none' in parts
	mut non_none := []string{}
	for part in parts {
		if part != 'none' {
			non_none << part
		}
	}
	if non_none.len == 0 {
		return 'Any'
	}
	if non_none.len == 1 && has_none {
		return '?${non_none[0]}'
	}
	if has_none {
		return '${non_none.join(' | ')} | none'
	}
	return non_none.join(' | ')
}

fn (h ClassFieldsHandler) infer_init_value_type(value_expr ?ast.Expression, arg_type_map map[string]string, env &ClassVisitEnv) string {
	val := value_expr or { return 'Any' }

	if val is ast.Name && val.id in arg_type_map {
		return arg_type_map[val.id]
	}
	return guess_type(val, env)
}

fn (h ClassFieldsHandler) collect_init_field_types(body []ast.Statement, self_name string, arg_type_map map[string]string, mut env ClassVisitEnv) map[string]string {
	mut field_types := map[string]string{}
	h.collect_init_field_types_from_body(body, self_name, arg_type_map, mut field_types, mut
		env)
	return field_types
}

fn (h ClassFieldsHandler) collect_init_field_types_from_body(body []ast.Statement, self_name string, arg_type_map map[string]string, mut field_types map[string]string, mut env ClassVisitEnv) {
	for stmt in body {
		match stmt {
			ast.Assign {
				for target in stmt.targets {
					h.collect_init_field_type_from_target(target, self_name, stmt.value,
						arg_type_map, mut field_types, mut env)
				}
			}
			ast.AnnAssign {
				h.collect_init_field_type_from_target(stmt.target, self_name, stmt.value,
					arg_type_map, mut field_types, mut env)
			}
			ast.If {
				h.collect_init_field_types_from_body(stmt.body, self_name, arg_type_map, mut
					field_types, mut env)
				h.collect_init_field_types_from_body(stmt.orelse, self_name, arg_type_map, mut
					field_types, mut env)
			}
			ast.For {
				h.collect_init_field_types_from_body(stmt.body, self_name, arg_type_map, mut
					field_types, mut env)
				h.collect_init_field_types_from_body(stmt.orelse, self_name, arg_type_map, mut
					field_types, mut env)
			}
			ast.While {
				h.collect_init_field_types_from_body(stmt.body, self_name, arg_type_map, mut
					field_types, mut env)
				h.collect_init_field_types_from_body(stmt.orelse, self_name, arg_type_map, mut
					field_types, mut env)
			}
			ast.With {
				h.collect_init_field_types_from_body(stmt.body, self_name, arg_type_map, mut
					field_types, mut env)
			}
			ast.Try {
				h.collect_init_field_types_from_body(stmt.body, self_name, arg_type_map, mut
					field_types, mut env)
				for handler in stmt.handlers {
					h.collect_init_field_types_from_body(handler.body, self_name, arg_type_map, mut
						field_types, mut env)
				}
				h.collect_init_field_types_from_body(stmt.orelse, self_name, arg_type_map, mut
					field_types, mut env)
				h.collect_init_field_types_from_body(stmt.finalbody, self_name, arg_type_map, mut
					field_types, mut env)
			}
			else {}
		}
	}
}

fn (h ClassFieldsHandler) collect_init_field_type_from_target(target ast.Expression, self_name string, value_expr ?ast.Expression, arg_type_map map[string]string, mut field_types map[string]string, mut env ClassVisitEnv) {
	if target is ast.Attribute {
		if target.value is ast.Name && target.value.id == self_name {
			inferred := h.infer_init_value_type(value_expr, arg_type_map, &env)
			existing := field_types[target.attr] or { '' }
			field_types[target.attr] = h.merge_inferred_field_types(existing, inferred)
		}
	} else if target is ast.Tuple {
		for elt in target.elements {
			h.collect_init_field_type_from_target(elt, self_name, none, arg_type_map, mut
				field_types, mut env)
		}
	} else if target is ast.List {
		for elt in target.elements {
			h.collect_init_field_type_from_target(elt, self_name, none, arg_type_map, mut
				field_types, mut env)
		}
	}
}

fn (h ClassFieldsHandler) should_strip_init(_ string, default_val string) bool {
	if default_val.len == 0 {
		return false
	}
	if default_val == 'none' || default_val.contains('Any(NoneType{})')
		|| default_val.contains('unsafe { nil }') {
		return true
	}
	return false
}

fn (h ClassFieldsHandler) is_field_mutated(struct_name string, field_name string, orig_name string, env &ClassVisitEnv) bool {
	base_struct_name := struct_name.replace('_Impl', '')
	mut candidates := [field_name]
	if orig_name.len > 0 && orig_name != field_name {
		candidates << orig_name
	}
	for name in candidates {
		qualified := '${base_struct_name}.${name}'
		if m_info := env.analyzer.mutability_map[qualified] {
			if m_info.is_mutated {
				return true
			}
		}
		if m_info := env.analyzer.mutability_map[name] {
			if m_info.is_mutated {
				return true
			}
		}
	}
	return false
}

fn (h ClassFieldsHandler) get_field_def_info(name string, field_type string, struct_name string, default_val string, orig_name string, mut env ClassVisitEnv) FieldDefInfo {
	is_mutated := h.is_field_mutated(struct_name, name, orig_name, &env)
	normalized_type := h.normalize_field_type(field_type)
	// Add & to class types for fields, but not for interfaces
	mut final_type := normalized_type
	clean := final_type.trim_left('?!')
	mut def := '    ${name} ${final_type}'
	if default_val.len > 0 && !h.should_strip_init(field_type, default_val) {
		def += ' = ${default_val}'
	}
	return FieldDefInfo{
		name:       name
		orig_name:  if orig_name.len > 0 { orig_name } else { name }
		def:        def
		is_mutated: is_mutated
	}
}

fn (h ClassFieldsHandler) collect_mixin_fields(struct_name string, mut added_fields map[string]bool, is_main_struct bool, mut env ClassVisitEnv) []FieldDefInfo {
	mut fields := []FieldDefInfo{}
	if !is_main_struct {
		return fields
	}

	mixin_names := env.analyzer.main_to_mixins[struct_name] or { []string{} }
	for mixin_name in mixin_names {
		// In V, we check mixin_nodes if they are preserved as strings or nodes
		// For now, use collected class_vars if available
		vars := env.state.class_vars[mixin_name] or { []map[string]string{} }
		for v in vars {
			name := v['name']
			if name.len == 0 || name in added_fields {
				continue
			}
			added_fields[name] = true
			fields << h.get_field_def_info(name, v['type'], struct_name, v['value'], name, mut
				env)
		}
	}
	return fields
}

fn (h ClassFieldsHandler) collect_init_fields(node ast.ClassDef, mut added_fields map[string]bool, struct_name string, mut env ClassVisitEnv) []FieldDefInfo {
	mut fields := []FieldDefInfo{}
	for stmt in node.body {
		if stmt is ast.FunctionDef && stmt.name == '__init__' {
			if stmt.args.args.len == 0 {
				continue
			}
			self_name := stmt.args.args[0].arg
			mut arg_type_map := map[string]string{}
			for arg in stmt.args.args[1..] {
				if ann := arg.annotation {
					arg_type_map[arg.arg] = env.map_annotation_fn(ann)
				}
			}
			init_field_types := h.collect_init_field_types(stmt.body, self_name, arg_type_map, mut
				env)
			h.walk_init_body(stmt.body, self_name, mut fields, mut added_fields, struct_name,
				arg_type_map, init_field_types, mut env)
		}
	}
	return fields
}

fn (h ClassFieldsHandler) walk_init_body(body []ast.Statement, self_name string, mut fields []FieldDefInfo, mut added_fields map[string]bool, struct_name string, arg_type_map map[string]string, init_field_types map[string]string, mut env ClassVisitEnv) {
	for stmt in body {
		match stmt {
			ast.Assign {
				for target in stmt.targets {
					h.walk_init_expr(target, self_name, stmt.value, mut fields, mut added_fields,
						struct_name, arg_type_map, init_field_types, mut env)
				}
			}
			ast.AnnAssign {
				h.walk_init_expr(stmt.target, self_name, stmt.value, mut fields, mut added_fields,
					struct_name, arg_type_map, init_field_types, mut env)
			}
			ast.If {
				h.walk_init_body(stmt.body, self_name, mut fields, mut added_fields, struct_name,
					arg_type_map, init_field_types, mut env)
				h.walk_init_body(stmt.orelse, self_name, mut fields, mut added_fields,
					struct_name, arg_type_map, init_field_types, mut env)
			}
			ast.For {
				h.walk_init_body(stmt.body, self_name, mut fields, mut added_fields, struct_name,
					arg_type_map, init_field_types, mut env)
				h.walk_init_body(stmt.orelse, self_name, mut fields, mut added_fields,
					struct_name, arg_type_map, init_field_types, mut env)
			}
			ast.While {
				h.walk_init_body(stmt.body, self_name, mut fields, mut added_fields, struct_name,
					arg_type_map, init_field_types, mut env)
				h.walk_init_body(stmt.orelse, self_name, mut fields, mut added_fields,
					struct_name, arg_type_map, init_field_types, mut env)
			}
			ast.With {
				h.walk_init_body(stmt.body, self_name, mut fields, mut added_fields, struct_name,
					arg_type_map, init_field_types, mut env)
			}
			ast.Try {
				h.walk_init_body(stmt.body, self_name, mut fields, mut added_fields, struct_name,
					arg_type_map, init_field_types, mut env)
				for handler in stmt.handlers {
					h.walk_init_body(handler.body, self_name, mut fields, mut added_fields,
						struct_name, arg_type_map, init_field_types, mut env)
				}
				h.walk_init_body(stmt.orelse, self_name, mut fields, mut added_fields,
					struct_name, arg_type_map, init_field_types, mut env)
				h.walk_init_body(stmt.finalbody, self_name, mut fields, mut added_fields,
					struct_name, arg_type_map, init_field_types, mut env)
			}
			else {}
		}
	}
}

fn (h ClassFieldsHandler) walk_init_expr(target ast.Expression, self_name string, value_expr ?ast.Expression, mut fields []FieldDefInfo, mut added_fields map[string]bool, struct_name string, arg_type_map map[string]string, init_field_types map[string]string, mut env ClassVisitEnv) {
	if target is ast.Attribute {
		if target.value is ast.Name && target.value.id == self_name {
			orig_name := target.attr
			field_name := sanitize_name(orig_name, false)
			if field_name in added_fields {
				return
			}
			added_fields[field_name] = true

			mut f_type := 'Any'
			if t0 := env.analyzer.type_map['${struct_name}.${orig_name}'] {
				f_type = t0
			}
			if f_type in ['Any', 'none', 'unknown'] {
				f_type = init_field_types[orig_name] or {
					h.infer_init_value_type(value_expr, arg_type_map, &env)
				}
			}
			env.analyzer.type_map['${struct_name}.${orig_name}'] = f_type
			if struct_name.ends_with('_Impl') {
				base_struct_name := struct_name.replace('_Impl', '')
				env.analyzer.type_map['${base_struct_name}.${orig_name}'] = f_type
			} else {
				env.analyzer.type_map['${struct_name}_Impl.${orig_name}'] = f_type
			}
			if f_type == 'Any' {
				if val := value_expr {
					if val is ast.Name && val.id in arg_type_map {
						f_type = arg_type_map[val.id]
					} else {
						f_type = guess_type(val, &env)
					}
				}
			}
			if val := value_expr {
				if val is ast.Constant && val.value == 'None' {
					if f_type.len > 0 && !f_type.starts_with('?') && f_type != 'Any' && f_type != 'none' && f_type != 'NoneType' {
						f_type = '?${f_type}'
					}
				}
			}
			fields << h.get_field_def_info(field_name, map_python_type(f_type, struct_name,
				false, mut env, orig_name), struct_name, '', orig_name, mut env)
		}
	} else if target is ast.Tuple {
		for elt in target.elements {
			h.walk_init_expr(elt, self_name, none, mut fields, mut added_fields, struct_name,
				arg_type_map, init_field_types, mut env)
		}
	} else if target is ast.List {
		for elt in target.elements {
			h.walk_init_expr(elt, self_name, none, mut fields, mut added_fields, struct_name,
				arg_type_map, init_field_types, mut env)
		}
	}
}

fn (h ClassFieldsHandler) process_class_attributes(body []ast.Statement, struct_name string, mut added_fields map[string]bool, is_dataclass bool, is_typed_dict bool, dataclass_m map[string]string, mut d_field_order []string, mut env ClassVisitEnv) []FieldDefInfo {
	mut fields := []FieldDefInfo{}

	for stmt in body {
		if stmt is ast.AnnAssign {
			if stmt.target is ast.Name {
				orig_name := stmt.target.id
				field_name := sanitize_name(orig_name, false)
				if field_name in added_fields {
					continue
				}

				// If dataclass handles it later, skip
				if is_dataclass && dataclass_m.len > 0 {
					continue
				}

				added_fields[field_name] = true
				field_type := env.map_annotation_fn(stmt.annotation)
				raw_type := env.map_annotation_fn(stmt.annotation)

				is_class_var := raw_type.contains('ClassVar[') || raw_type.starts_with('ClassVar')
				is_init_var := raw_type.contains('InitVar[') || raw_type.starts_with('InitVar')
				is_readonly := raw_type.contains('ReadOnly[') || raw_type.starts_with('ReadOnly')

				if (is_dataclass || is_typed_dict) && !is_class_var && !is_init_var {
					d_field_order << field_name
				}

				default_val := if v := stmt.value { env.visit_expr_fn(v) } else { '' }

				if is_class_var || is_init_var {
					if is_class_var {
						h.set_class_var(struct_name, field_name, field_type, if default_val.len > 0 {
							default_val
						} else {
							'none'
						}, mut env)
					} else if is_init_var {
						if struct_name !in env.state.dataclass_init_vars {
							env.state.dataclass_init_vars[struct_name] = map[string]string{}
						}
						// Extract type from InitVar[T]
						mut inner_type := field_type
						if inner_type.starts_with('InitVar[') && inner_type.ends_with(']') {
							inner_type = inner_type['InitVar['.len..inner_type.len - 1]
						} else if inner_type == 'InitVar' {
							inner_type = 'Any'
						}
						env.state.dataclass_init_vars[struct_name][field_name] = inner_type
					}
				} else {
					mut info := h.get_field_def_info(field_name, field_type, struct_name,
						default_val, orig_name, mut env)
					info.is_readonly = is_readonly
					fields << info

					// Register for lookups
					env.analyzer.type_map['${struct_name}.${orig_name}'] = field_type
					if struct_name.ends_with('_Impl') {
						base_struct_name := struct_name.replace('_Impl', '')
						env.analyzer.type_map['${base_struct_name}.${orig_name}'] = field_type
					}
				}
			}
		} else if stmt is ast.Assign {
			for target in stmt.targets {
				if target is ast.Name {
					orig_name := target.id
					field_name := sanitize_name(orig_name, false)

					if orig_name == '__slots__' {
						h.parse_slots(stmt.value, mut fields, mut added_fields, struct_name, mut
							env)
						continue
					}

					if field_name in added_fields {
						continue
					}
					added_fields[field_name] = true
					if is_dataclass {
						d_field_order << field_name
					}

					field_type := map_python_type(guess_type(stmt.value, &env), struct_name,
						false, mut env, orig_name)
					default_val := env.visit_expr_fn(stmt.value)
					h.set_class_var(struct_name, field_name, field_type, default_val, mut
						env)
				}
			}
		}
	}
	return fields
}

fn (h ClassFieldsHandler) parse_slots(value ast.Expression, mut fields []FieldDefInfo, mut added_fields map[string]bool, struct_name string, mut env ClassVisitEnv) {
	mut slots := []string{}
	match value {
		ast.List {
			for elt in value.elements {
				if elt is ast.Constant {
					slots << elt.value.trim('\'"')
				}
			}
		}
		ast.Tuple {
			for elt in value.elements {
				if elt is ast.Constant {
					slots << elt.value.trim('\'"')
				}
			}
		}
		ast.Constant {
			slots << value.value.trim('\'"')
		}
		else {}
	}
	for slot in slots {
		f_name := sanitize_name(slot, false)
		if f_name in added_fields {
			continue
		}
		added_fields[f_name] = true
		fields << h.get_field_def_info(f_name, 'Any', struct_name, '', slot, mut env)
	}
}

fn (h ClassFieldsHandler) set_class_var(struct_name string, name string, field_type string, value string, mut env ClassVisitEnv) {
	mut class_vars := env.state.class_vars[struct_name] or { []map[string]string{} }
	class_vars << {
		'name':  name
		'type':  field_type
		'value': if value.len > 0 { value } else { 'none' }
	}
	env.state.class_vars[struct_name] = class_vars
}

fn (h ClassFieldsHandler) process_dataclass_fields(body []ast.Statement, struct_name string, dataclass_metadata map[string]string, mut added_fields map[string]bool, mut d_field_order []string, mut env ClassVisitEnv) []FieldDefInfo {
	if dataclass_metadata.len == 0 {
		return []FieldDefInfo{}
	}
	mut fields := []FieldDefInfo{}

	// dataclass_metadata in V is currently map[string]string, we need to parse it or pass structured data
	// For now, it might contain a comma-separated list of attributes or something
	// But let's assume it should follow the Python logic if possible
	return fields
}

fn (h ClassFieldsHandler) generate_dataclass_factory(struct_name string, dataclass_m map[string]string, body []ast.Statement, has_post_init bool, mut env ClassVisitEnv) ?string {
	if !has_post_init {
		return none
	}
	factory_name := get_factory_name(struct_name, &env)

	mut factory_args := []string{}
	mut struct_init := []string{}
	mut post_init_args := []string{}

	// Dataclass attributes are usually in node body
	for stmt in body {
		if stmt is ast.AnnAssign {
			if stmt.target is ast.Name {
				name := sanitize_name(stmt.target.id, false)
				raw_type := env.map_annotation_fn(stmt.annotation)

				if val := stmt.value {
					if struct_name !in env.state.dataclass_defaults {
						env.state.dataclass_defaults[struct_name] = map[string]string{}
					}
					env.state.dataclass_defaults[struct_name][name] = env.visit_expr_fn(val)
				}

				is_init_var := raw_type.contains('InitVar[') || raw_type.starts_with('InitVar')
				is_class_var := raw_type.contains('ClassVar[') || raw_type.starts_with('ClassVar')
				if is_class_var {
					continue
				}

				f_type := if is_init_var {
					mut t := map_python_type(raw_type, struct_name, false, mut env, name)
					if t.starts_with('InitVar[') && t.ends_with(']') {
						t['InitVar['.len..t.len - 1]
					} else if t == 'InitVar' {
						'Any'
					} else {
						t
					}
				} else {
					map_python_type(raw_type, struct_name, false, mut env, name)
				}

				factory_args << '${name} ${f_type}'
				if !is_init_var {
					struct_init << '${name}: ${name}'
				} else {
					post_init_args << name
				}
			}
		}
	}

	prefix := if env.state.is_exported(struct_name) { 'pub ' } else { '' }
	generics := get_generics_with_variance_str(&env)

	// InitVars are already handled in the loop above if they are present in the body
	// but we might have collected more from other places (like bases, though unlikely for now)
	// For now, let's assume the loop above is enough for the local class definition.

	// Add InitVars to factory args and post_init call
	// Note: Local InitVars are already handled in the AnnAssign loop above.
	// We might still need to handle InitVars from base classes if dataclass_init_vars
	// was populated from bases (though currently it isn't).

	mut code := []string{}
	code << '${prefix}fn ${factory_name}${generics}(${factory_args.join(', ')}) &${struct_name}${generics} {'
	code << '    mut self := &${struct_name}${generics}{${struct_init.join(', ')}}'
	code << '    self.post_init(${post_init_args.join(', ')})'
	code << '    return self'
	code << '}'

	return code.join('\n')
}

fn (h ClassFieldsHandler) get_namedtuple_metadata(node ast.ClassDef, struct_name string, env &ClassVisitEnv) ?map[string]string {
	for key, sig in env.analyzer.call_signatures {
		if sig.namedtuple_metadata.len == 0 {
			continue
		}
		if key.starts_with('${node.name}@') || key.starts_with('${struct_name}@') {
			return sig.namedtuple_metadata
		}
	}
	return none
}

fn (h ClassFieldsHandler) get_dataclass_metadata(node ast.ClassDef, struct_name string, env &ClassVisitEnv) ?map[string]string {
	for key, sig in env.analyzer.call_signatures {
		if sig.dataclass_metadata.len == 0 {
			continue
		}
		if key.starts_with('${node.name}@') || key.starts_with('${struct_name}@') {
			return sig.dataclass_metadata
		}
	}
	return none
}

fn (h ClassFieldsHandler) process_namedtuple_fields(struct_name string, nt_metadata map[string]string, mut added_fields map[string]bool, mut env ClassVisitEnv) []FieldDefInfo {
	mut fields := []FieldDefInfo{}
	// NT metadata parsing logic here
	return fields
}

fn (h ClassFieldsHandler) build_visibility_blocks(fields []FieldDefInfo, mut output []string, is_typed_dict bool) {
	mut embed_fields := []string{}
	mut pub_fields := []string{}
	mut pub_mut_fields := []string{}
	mut priv_fields := []string{}
	mut priv_mut_fields := []string{}

	for f in fields {
		is_private := f.orig_name.starts_with('_')
		is_impl := f.def.contains('_Impl')
		if is_typed_dict {
			if f.is_readonly {
				pub_fields << f.def
			} else {
				pub_mut_fields << f.def
			}
		} else if is_impl {
			embed_fields << f.def
		} else if is_private {
			if f.is_mutated {
				priv_mut_fields << f.def
			} else {
				priv_fields << f.def
			}
		} else {
			if f.is_readonly {
				pub_fields << f.def
			} else {
				pub_mut_fields << f.def
			}
		}
	}

	if embed_fields.len > 0 {
		for f in embed_fields {
			output << f
		}
	}
	if priv_fields.len > 0 {
		for f in priv_fields {
			output << f
		}
	}
	if pub_fields.len > 0 {
		output << 'pub:'
		for f in pub_fields {
			output << f
		}
	}
	if pub_mut_fields.len > 0 {
		output << 'pub mut:'
		for f in pub_mut_fields {
			output << f
		}
	}
	if priv_mut_fields.len > 0 {
		output << 'mut:'
		for f in priv_mut_fields {
			output << f
		}
	}
}

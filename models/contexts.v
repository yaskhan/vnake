module models

pub struct TypeGuessingContext {
pub mut:
	type_map           map[string]string
	location_map       map[string]string
	known_v_types      map[string]string
	name_remap         map[string]string
	defined_classes    map[string]map[string]bool
	explicit_any_types map[string]bool
	target_type        string
	analyzer           voidptr = unsafe { nil }
}

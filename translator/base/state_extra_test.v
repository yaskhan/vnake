module base

fn test_get_scc_prefix_simple() {
	assert get_scc_prefix('test.py') == 'test'
}

fn test_get_scc_prefix_forward_slash() {
	assert get_scc_prefix('path/to/file.py') == 'path__to__file'
}

fn test_get_scc_prefix_back_slash() {
	assert get_scc_prefix('path\\to\\file.py') == 'path__to__file'
}

fn test_get_scc_prefix_multiple_dots() {
	assert get_scc_prefix('my.module.file.py') == 'my__module__file'
}

fn test_get_scc_prefix_empty() {
	assert get_scc_prefix('') == 'py_mod'
}

fn test_get_scc_prefix_dot_py_only() {
	assert get_scc_prefix('.py') == 'py_mod'
}

fn test_get_scc_prefix_no_extension() {
	assert get_scc_prefix('plain_file') == 'plain_file'
}

fn test_get_scc_prefix_mixed_separators() {
	assert get_scc_prefix('root/sub.dir\\file.py') == 'root__sub__dir__file'
}

fn test_get_scc_prefix_case_sensitive() {
	// Note: .replace('.py', '') is case sensitive in the current implementation
	assert get_scc_prefix('FILE.PY') == 'FILE__PY'
}

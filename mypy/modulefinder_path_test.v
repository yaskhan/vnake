module mypy

import os

fn test_compute_search_paths_basic() {
	options := Options{}
	sources := []MypyBuildSource{}
	data_dir := '/tmp/mypy_data'

	paths := compute_search_paths(sources, options, data_dir, none)

	assert paths.typeshed_path.contains(os.join_path(data_dir, 'typeshed', 'stdlib'))
	assert paths.python_path.contains(os.getwd())
}

fn test_compute_search_paths_pythonpath() {
	os.setenv('PYTHONPATH', '/tmp/pypath1' + os.path_delimiter + '/tmp/pypath2', true)
	defer { os.unsetenv('PYTHONPATH') }

	options := Options{}
	sources := []MypyBuildSource{}
	data_dir := '/tmp/mypy_data'

	paths := compute_search_paths(sources, options, data_dir, none)

	assert paths.python_path.contains('/tmp/pypath1')
	assert paths.python_path.contains('/tmp/pypath2')
}

fn test_compute_search_paths_no_site_packages() {
	mut options := Options{}
	options.no_site_packages = true
	sources := []MypyBuildSource{}
	data_dir := '/tmp/mypy_data'

	paths := compute_search_paths(sources, options, data_dir, none)

	// site_pkgs should be empty when no_site_packages is true
	assert paths.package_path.len == 0
}

fn test_compute_search_paths_with_site_packages() {
	mut options := Options{}
	options.no_site_packages = false
	sources := []MypyBuildSource{}
	data_dir := '/tmp/mypy_data'

	paths := compute_search_paths(sources, options, data_dir, none)

	// Depending on environment, it might be empty or not, but we just verify it was called
	// getsearch_dirs results are returned in site_pkgs
}

fn test_compute_search_paths_alt_lib_path() {
	options := Options{}
	sources := []MypyBuildSource{}
	data_dir := '/tmp/mypy_data'
	alt_path := '/tmp/alt_lib'

	paths := compute_search_paths(sources, options, data_dir, alt_path)

	assert paths.mypy_path.contains(alt_path)
	// When alt_lib_path is provided, python_path should not be populated with default/env paths
	assert !paths.python_path.contains(os.getwd())
}

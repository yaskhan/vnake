module mypy

import os
import time

fn create_test_temp_dir() string {
	root := os.join_path(os.temp_dir(), 'mypy_find_sources_${time.now().unix_nano()}')
	os.mkdir_all(root) or { panic(err.msg()) }
	return os.abs_path(root)
}

fn write_test_file(path string, contents string) {
	os.mkdir_all(os.dir(path)) or { panic(err.msg()) }
	os.write_file(path, contents) or { panic(err.msg()) }
}

fn collect_sources_by_module(sources []BuildSource) map[string]BuildSource {
	mut result := map[string]BuildSource{}
	for source in sources {
		result[source.module] = source
	}
	return result
}

fn test_create_source_list_discovers_modules_in_directory_tree() {
	root := create_test_temp_dir()
	defer {
		os.rmdir_all(root) or {}
	}

	write_test_file(os.join_path(root, 'top.py'), 'x = 1\n')
	write_test_file(os.join_path(root, 'pkg', '__init__.py'), '')
	write_test_file(os.join_path(root, 'pkg', 'mod.py'), 'y = 2\n')

	options := Options.new()
	sources := create_source_list([root], *options, none, false) or { panic(err.msg()) }
	by_module := collect_sources_by_module(sources)

	assert sources.len == 3
	assert by_module['top'].path == os.join_path(root, 'top.py')
	assert by_module['pkg'].path == os.join_path(root, 'pkg', '__init__.py')
	assert by_module['pkg.mod'].path == os.join_path(root, 'pkg', 'mod.py')
	assert by_module['pkg.mod'].base_dir == root
}

fn test_find_sources_in_dir_prefers_stub_files_for_same_module_name() {
	root := create_test_temp_dir()
	defer {
		os.rmdir_all(root) or {}
	}

	write_test_file(os.join_path(root, 'pkg.py'), 'x = 1\n')
	write_test_file(os.join_path(root, 'pkg.pyi'), 'x: int\n')

	options := Options.new()
	sources := create_source_list([root], *options, none, false) or { panic(err.msg()) }

	assert sources.len == 1
	assert sources[0].module == 'pkg'
	assert sources[0].path == os.join_path(root, 'pkg.pyi')
}

fn test_create_source_list_respects_explicit_package_bases() {
	root := create_test_temp_dir()
	defer {
		os.rmdir_all(root) or {}
	}

	base_dir := os.join_path(root, 'src')
	module_path := os.join_path(base_dir, 'pkg', 'mod.py')
	write_test_file(module_path, 'z = 3\n')

	mut options := Options.new()
	options.explicit_package_bases = true
	options.mypy_path = [base_dir]

	sources := create_source_list([module_path], *options, none, false) or { panic(err.msg()) }

	assert sources.len == 1
	assert sources[0].module == 'pkg.mod'
	assert sources[0].base_dir == base_dir
}

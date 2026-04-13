module main

import analyzer
import os
import translator
import ast
import mypy
import utils

pub struct TranspilerConfig {
pub mut:
	warn_dynamic        bool
	no_helpers          bool
	helpers_only        bool
	include_all_symbols bool
	strict_exports      bool
	experimental        bool
	run                 bool
	analyze_deps        bool
	skip_dirs           []string
}

pub struct GlobalHelpers {
pub mut:
	imports   []string
	structs   []string
	functions []string
	classes   []string
}

pub fn new_global_helpers() GlobalHelpers {
	return GlobalHelpers{
		imports:   []string{}
		structs:   []string{}
		functions: []string{}
		classes:   []string{}
	}
}

pub fn (mut g GlobalHelpers) merge(trans &translator.Translator) {
	for imp in trans.get_helper_imports() {
		if imp !in g.imports {
			g.imports << imp
		}
	}
	for s in trans.get_helper_structs() {
		if s !in g.structs {
			g.structs << s
		}
	}
	for f in trans.get_helper_functions() {
		if f !in g.functions {
			g.functions << f
		}
	}

	for k, _ in trans.state.defined_classes {
		v_cls := trans.state.class_to_impl[k] or { k }
		if v_cls !in g.classes {
			g.classes << v_cls
		}
	}
}

pub fn (g GlobalHelpers) write(path string, module_name string) bool {
	v_code := translator.VCodeEmitter.emit_global_helpers(g.imports, g.structs, g.functions,
		module_name, g.classes)
	os.write_file(path, v_code) or {
		println('Error writing global helpers to ${path}: ${err}')
		return false
	}
	println('Generated global helpers: ${path}')
	return true
}

fn is_python_file(path string) bool {
	return path.ends_with('.py') || path.ends_with('.pyi')
}

fn relative_path(root string, path string) string {
	root_norm := root.replace('\\', '/').trim_right('/')
	path_norm := path.replace('\\', '/')
	if root_norm.len == 0 {
		return path_norm.trim_left('/')
	}
	if path_norm.starts_with(root_norm) {
		return path_norm[root_norm.len..].trim_left('/')
	}
	return path_norm
}

fn should_skip_path(rel_path string, skip_dirs []string) bool {
	for skip in skip_dirs {
		skip_norm := skip.replace('\\', '/').trim('/')
		if skip_norm.len == 0 {
			continue
		}
		if rel_path == skip_norm || rel_path.starts_with('${skip_norm}/') {
			return true
		}
	}
	return false
}

pub fn generate_all_helpers(output_path string) bool {
	mut trans := translator.new_translator()

	// Force all flags to True to generate every possible helper
	trans.state.used_complex = true
	trans.state.used_string_format = true
	trans.state.used_list_concat = true
	trans.state.used_dict_merge = true

	builtins := ['sorted', 'reversed', 'round', 'py_subscript', 'py_slice', 'py_repr', 'py_ascii',
		'py_format', 'py_string_format_map']
	for b in builtins {
		trans.state.used_builtins[b] = true
	}

	modules_to_fake := [
		'tempfile',
		'logging',
		'argparse',
		'pathlib',
		'collections',
		'itertools',
		'functools',
		'operator',
		'threading',
		'socket',
		'http.client',
		'csv',
		'sqlite3',
		'subprocess',
		'platform',
		'hashlib',
		'urllib.parse',
		'struct',
		'array',
		'fractions',
		'statistics',
		'decimal',
		'pickle',
		'zlib',
		'gzip',
		'copy',
	]

	for i, mod in modules_to_fake {
		trans.state.imported_modules['fake${i}'] = mod
	}

	// Trigger empty translation to collect helpers
	trans.translate('pass', 'fake.py')

	helpers_code := translator.VCodeEmitter.emit_global_helpers(trans.get_helper_imports(),
		trans.get_helper_structs(), trans.get_helper_functions(), 'main', [])

	os.write_file(output_path, helpers_code) or {
		println('Error writing global helpers to ${output_path}: ${err}')
		return false
	}
	println('Success: generated global helper library at ${output_path}')
	return true
}

pub fn transpile_file(source_file string, config TranspilerConfig, mut global_helpers GlobalHelpers, current_module string, scc_files []string, output_path string) bool {
	eprintln('DEBUG: transpile_file START ${source_file}')
	println('Transpiling ${source_file} (module: ${current_module})...')

	source_code := os.read_file(source_file) or {
		println('Error reading ${source_file}: ${err}')
		return false
	}

	// Pre-process source
	comp := utils.new_compatibility_layer()
	processed_source := comp.preprocess_source(source_code)

	// Build Mypy Analysis
	mut lexer := ast.new_lexer(processed_source, source_file)
	mut parser := ast.new_parser(lexer)
	tree := parser.parse_module()

	mut options := mypy.Options.new()
	mut errors := mypy.new_errors(options)
	mut api := mypy.new_api(options, &errors)

	mut file := mypy.bridge(tree) or {
		println('Error: Mypy bridge failed for ${source_file}')
		return false
	}

	file.path = source_file

	tc := api.check(mut file, map[string]&mypy.MypyFile{}) or {
		println('Mypy analysis error in ${source_file}: ${err}')
		// Report errors from Mypy reporter if any
		mut error_output := []string{}
		for _, info_list in errors.error_info_map {
			for info in info_list {
				code_str := info.code or { '' }
				error_output << '${info.file}:${info.line}:${info.column}: [${code_str}] ${info.message}'
			}
		}
		if error_output.len > 0 {
			full_error := error_output.join('\n')
			println(full_error)
			tips := analyzer.get_mypy_tips(full_error)
			if tips.len > 0 {
				println(tips)
			}
		}
		return false
	}

	mut plugin_analyzer := analyzer.new_mypy_plugin_analyzer()

	// Import persistent types from Mypy - CRITICAL for globals and complex expressions
	eprintln('DEBUG: main.v persistent_type_map len=${tc.persistent_type_map.len}')
	for pkey, t in tc.persistent_type_map {
		parts := pkey.split(':')
		if parts.len >= 3 {
			loc := '${parts[0]}:${parts[1]}'
			expr_str := parts[2..].join(':')
			t_str := t.type_str()
			plugin_analyzer.store.collect_type(expr_str, loc, t_str)
			plugin_analyzer.store.collect_type('@', loc, t_str)

			if expr_str.contains('.') {
				p_parts := expr_str.split('.')
				if p_parts.len > 0 {
					last_p := p_parts[p_parts.len - 1]
					plugin_analyzer.store.collect_type(last_p, loc, t_str)
				}
			}
		}
	}

	plugin_analyzer.collect_file_with_checker(mut file, tc)

	// Translation
	mut trans := translator.new_translator()
	trans.state.type_inference = voidptr(&plugin_analyzer.store)
	trans.analyzer.load_mypy_data(plugin_analyzer.store)
	trans.state.include_all_symbols = config.include_all_symbols
	trans.state.strict_exports = config.strict_exports
	trans.state.current_module_name = current_module
	trans.state.current_file_name = os.file_name(source_file)
	trans.state.is_full_module = true
	if !config.no_helpers {
		trans.state.omit_builtins = true
	}
	for f in scc_files {
		trans.state.scc_files[f] = true
	}

	v_code := trans.translate(processed_source, source_file)

	// Report warnings
	for warning in trans.state.warnings {
		println('Warning: ${warning}')
	}

	final_output := if output_path.len > 0 {
		output_path
	} else if source_file.ends_with('.pyi') {
		source_file[..source_file.len - 4] + '.v'
	} else if source_file.ends_with('.py') {
		source_file[..source_file.len - 3] + '.v'
	} else {
		source_file + '.v'
	}

	if !config.helpers_only {
		os.write_file(final_output, v_code) or {
			println('Error writing ${final_output}: ${err}')
			return false
		}
	}

	if !config.no_helpers {
		global_helpers.merge(trans)
	}

	if output_path.len == 0 {
		// Standalone mode: write helpers if not merged
		if !config.no_helpers {
			base_name := os.file_name(source_file).all_before_last('.')
			helpers_file := os.join_path(os.dir(final_output), '${base_name}_helpers.v')
			mut standalone_helpers := new_global_helpers()
			standalone_helpers.merge(trans)
			standalone_helpers.write(helpers_file, 'main')
		}
	}

	return true
}

pub fn process_directory(path string, mut config TranspilerConfig, recursive bool) {
	fmt_path := path.replace('\\', '/')
	println('Processing directory: ${fmt_path} (recursive=${recursive})')

	mut dep_analyzer := analyzer.new_dependency_analyzer()
	sccs := dep_analyzer.find_sccs(path, recursive, config.skip_dirs)
	println('Found ${sccs.len} SCCs')

	mut file_to_scc_idx := map[string]int{}
	for idx, scc in sccs {
		for f in scc {
			file_to_scc_idx[f] = idx
		}
	}

	mut scc_to_dir := map[int]string{}
	mut scc_to_module := map[int]string{}
	for idx, scc in sccs {
		if scc.len > 1 {
			first_file := scc[0]
			scc_dir := os.dir(os.join_path(path, first_file))
			scc_to_dir[idx] = scc_dir
			dir_name := os.file_name(scc_dir)
			scc_to_module[idx] = if dir_name.len > 0 { dir_name } else { 'models' }
		} else {
			scc_dir := os.dir(os.join_path(path, scc[0]))
			scc_to_dir[idx] = scc_dir
			scc_to_module[idx] = 'main'
		}
	}

	mut dir_to_files := map[string][]string{}
	for f, idx in file_to_scc_idx {
		d := scc_to_dir[idx]
		dir_to_files[d] << f
	}

	for d, files in dir_to_files {
		mut global_helpers := new_global_helpers()
		mut processed_files := 0

		mut current_module := 'main'
		for f in files {
			idx := file_to_scc_idx[f]
			if sccs[idx].len > 1 {
				current_module = scc_to_module[idx]
				break
			}
		}

		for f in files {
			full_path := os.join_path(path, f)
			idx := file_to_scc_idx[f]
			scc := sccs[idx]

			base_out := os.file_name(f).all_before_last('.') + '.v'
			output_path := os.join_path(d, base_out)

			if transpile_file(full_path, config, mut global_helpers, current_module, scc,
				output_path)
			{
				processed_files++
			}
		}

		if processed_files > 0 && !config.no_helpers {
			helpers_file := os.join_path(d, 'vnake_helpers.v')
			global_helpers.write(helpers_file, current_module)
		}
	}
}

pub fn run_v_code(v_file string, helpers_file string) bool {
	v_file_abs := os.abs_path(v_file)
	base_name := os.file_name(v_file_abs).all_before_last('.')

	// Create isolated temp directory for compilation
	tmp_dir := os.join_path(os.temp_dir(), 'vnake_run_${base_name}')
	os.mkdir(tmp_dir) or {}

	// Copy main file and helpers to temp dir
	v_content := os.read_file(v_file_abs) or { '' }
	out_v := os.join_path(tmp_dir, '${base_name}.v')
	os.write_file(out_v, v_content) or {}

	if helpers_file.len > 0 && os.exists(helpers_file) {
		h_content := os.read_file(helpers_file) or { '' }
		out_h := os.join_path(tmp_dir, '${base_name}_helpers.v')
		os.write_file(out_h, h_content) or {}
	}

	println('Compiling and running: ${os.file_name(v_file_abs)}')
	println('-'.repeat(50))

	// Run only our files from temp directory (isolated)
	mut p := os.new_process(@VEXE)
	p.set_args(['-enable-globals', 'run', tmp_dir])
	p.run()
	p.wait()

	exit_code := p.code
	p.close()

	// Clean up temp directory
	os.rmdir_all(tmp_dir) or {}

	println('-'.repeat(50))
	if exit_code != 0 {
		println('V compilation/execution failed with exit code: ${exit_code}')
		return false
	}
	return true
}

pub fn print_banner() {
	banner := '
=================================================================
                    Vnake Transpiler
              Python to V Language Compiler
=================================================================

Usage: vnake <path> [options]

Arguments:
  path                  Path to Python file (.py/.pyi) or directory

Options:
  -r, --recursive       Recursively process directories
  --analyze-deps        Analyze dependencies (for directories)
  --warn-dynamic        Warn when falling back to dynamic Any type
  --no-helpers          Do not generate a helper V file
  --helpers-only        Only generate the helper V file
  --include-all-symbols Include all symbols (not just __all__)
  --strict-exports      Warn about symbols missing from __all__
  --experimental        Enable experimental PEP features
  --run                 Compile and run V code after transpilation
  -h, --help            Show this help message

Examples:
  vnake script.py                    # Transpile a single file
  vnake script.py --run              # Transpile and run V code
  vnake src/ -r                      # Transpile all files in directory
  vnake project/ --helpers-only      # Generate only helpers file

Quick Start:
  vnake your_script.py --run
=================================================================
'
	println(banner)
}

fn parse_args() (string, TranspilerConfig, bool) {
	mut path := ''
	mut recursive := false
	mut config := TranspilerConfig{
		skip_dirs: []string{}
	}

	for i := 1; i < os.args.len; i++ {
		arg := os.args[i]
		match arg {
			'-r', '--recursive' {
				recursive = true
			}
			'--analyze-deps' {
				config.analyze_deps = true
			}
			'--warn-dynamic' {
				config.warn_dynamic = true
			}
			'--no-helpers' {
				config.no_helpers = true
			}
			'--helpers-only' {
				config.helpers_only = true
			}
			'--include-all-symbols' {
				config.include_all_symbols = true
			}
			'--strict-exports' {
				config.strict_exports = true
			}
			'--experimental' {
				config.experimental = true
			}
			'--run' {
				config.run = true
			}
			'--skip-dir' {
				if i + 1 < os.args.len {
					config.skip_dirs << os.args[i + 1]
					i++
				}
			}
			'-h', '--help' {
				print_banner()
				exit(0)
			}
			else {
				if arg.starts_with('--skip-dir=') {
					config.skip_dirs << arg.all_after('=')
				} else if arg.len > 0 && !arg.starts_with('-') && path.len == 0 {
					path = arg
				}
			}
		}
	}

	return path, config, recursive
}

fn print_dependency_report(path string, recursive bool, config TranspilerConfig) {
	mut dep_analyzer := analyzer.new_dependency_analyzer()
	println('Analyzing dependencies for: ${path}')
	graph := dep_analyzer.analyze_project(path, recursive, config.skip_dirs)
	mut files := graph.keys()
	files.sort()
	for file in files {
		deps := graph[file]
		if deps.len == 0 {
			println('${file}: No imports')
		} else {
			println('${file}: ${deps.join(', ')}')
		}
	}
}

fn main() {
	println('DEBUG: main.v START')
	if os.args.len == 1 {
		print_banner()
		return
	}

	path, mut config, recursive := parse_args()
	if path.len == 0 {
		print_banner()
		return
	}

	if !os.exists(path) {
		println("Error: Path '${path}' not found.")
		exit(1)
	}

	if config.analyze_deps {
		if !os.is_dir(path) {
			println('Error: --analyze-deps requires a directory.')
			exit(1)
		}
		print_dependency_report(path, recursive, config)
		return
	}

	if config.helpers_only {
		output_dir := if os.is_dir(path) {
			path
		} else {
			os.dir(path)
		}
		mut target_dir := output_dir
		if target_dir.len == 0 || target_dir == '.' {
			target_dir = os.getwd()
		}
		output_path := os.join_path(target_dir, 'vnake_helpers.v')
		if !generate_all_helpers(output_path) {
			exit(1)
		}
		return
	}

	if os.is_file(path) {
		if !is_python_file(path) {
			println('Error: Input file must be a Python script (.py or .pyi)')
			exit(1)
		}
		mut helpers := new_global_helpers()
		if !transpile_file(path, config, mut helpers, 'main', [], '') {
			exit(1)
		}

		if config.run {
			v_file := path.all_before_last('.') + '.v'
			helpers_file := if config.no_helpers {
				''
			} else {
				path.all_before_last('.') + '_helpers.v'
			}
			run_v_code(v_file, helpers_file)
		}
		return
	}

	if os.is_dir(path) {
		process_directory(path, mut config, recursive)
		return
	}

	println('Error: Invalid path type.')
	exit(1)
}

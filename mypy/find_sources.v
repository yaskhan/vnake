// find_sources.v — Routines for finding sources that mypy will check
// Translated from mypy/find_sources.py to V 0.5.x
//
// Work in progress by Antigravity. Started: 2026-03-22 15:00

module mypy

import os
import regex

// PY_EXTENSIONS — Python file extensions
pub const py_extensions = ['.pyi', '.py']

// InvalidSourceList — exception for source list problems
pub struct InvalidSourceList {
pub:
	msg string
}

pub fn (e InvalidSourceList) msg() string {
	return e.msg
}

// create_source_list creates a list of BuildSource from a list of paths
pub fn create_source_list(paths []string,
	options Options,
	fscache ?&FileSystemCache,
	allow_empty_dir bool) ![]BuildSource {
	_ = fscache
	mut finder := new_source_finder(options)

	mut sources := []BuildSource{}
	for path in paths {
		mut clean_path := os.norm_path(path)
		if clean_path.ends_with('.py') || clean_path.ends_with('.pyi') {
			name, base_dir := finder.crawl_up(clean_path)
			sources << BuildSource{
				path:     clean_path
				module:   name
				base_dir: base_dir
			}
		} else if finder.is_dir(clean_path) {
			sub_sources := finder.find_sources_in_dir(clean_path)
			if sub_sources.len == 0 && !allow_empty_dir {
				return error('There are no .py[i] files in directory \'${clean_path}\'')
			}
			for s in sub_sources {
				sources << s
			}
		} else {
			mod := if options.scripts_are_modules { os.base(clean_path) } else { '__main__' }
			sources << BuildSource{
				path:   clean_path
				module: mod
			}
		}
	}
	return sources
}

// keyfunc determines sort order for directory list
pub fn keyfunc(name string) string {
	base := name.all_before_last('.')
	ext := os.file_ext(name)
	init_weight := if base == '__init__' { '0' } else { '1' }
	ext_weight := match ext {
		'.pyi' { '0' }
		'.py' { '1' }
		else { '2' }
	}
	return '${init_weight}:${ext_weight}:${base}:${name}'
}

// normalise_package_base normalizes package base path
pub fn normalise_package_base(root string) string {
	mut r := root
	if r == '' {
		r = '.'
	}
	r = os.abs_path(r)
	if r.ends_with(os.path_separator) {
		r = r[..r.len - 1]
	}
	return r
}

// ---------------------------------------------------------------------------
// Rest of the file ...
// ---------------------------------------------------------------------------

// SourceFinder — source finder
pub struct SourceFinder {
pub mut:
	options                Options
	explicit_package_bases ?[]string
	namespace_packages     bool
	exclude                []string
	exclude_gitignore      bool
	verbosity              int
}

// new_source_finder creates a new SourceFinder
pub fn new_source_finder(options Options) SourceFinder {
	return SourceFinder{
		options:                options
		explicit_package_bases: get_explicit_package_bases(options)
		namespace_packages:     options.namespace_packages
		exclude:                options.exclude
		exclude_gitignore:      options.exclude_gitignore
		verbosity:              options.verbosity
	}
}

fn get_explicit_package_bases(options Options) ?[]string {
	if !options.explicit_package_bases {
		return none
	}
	mut roots := options.mypy_path.clone()
	roots << os.getwd()
	mut normalized := []string{}
	for root in roots {
		value := normalise_package_base(root)
		if value !in normalized {
			normalized << value
		}
	}
	return normalized
}

// is_explicit_package_base checks if path is an explicit package base
pub fn (f SourceFinder) is_explicit_package_base(path string) bool {
	if bases := f.explicit_package_bases {
		normalized := normalise_package_base(path)
		for base in bases {
			if base == normalized {
				return true
			}
		}
	}
	return false
}

pub fn (mut f SourceFinder) find_sources_in_dir(path string) []BuildSource {
	mut sources := []BuildSource{}
	mut seen := map[string]bool{}
	mut names := os.ls(path) or { return sources }
	names.sort_with_compare(fn (a &string, b &string) int {
		ka := keyfunc(*a)
		kb := keyfunc(*b)
		if ka < kb {
			return -1
		}
		if ka > kb {
			return 1
		}
		return 0
	})

	for name in names {
		if should_skip_source_name(name) {
			continue
		}
		subpath := os.join_path(path, name)
		if matches_source_exclude(subpath, f.exclude) {
			continue
		}
		if os.is_dir(subpath) {
			sub_sources := f.find_sources_in_dir(subpath)
			if sub_sources.len > 0 {
				seen[name] = true
				sources << sub_sources
			}
			continue
		}

		stem := strip_py(name) or { continue }
		if stem in seen {
			continue
		}
		seen[stem] = true
		module_name, base_dir := f.crawl_up(subpath)
		sources << BuildSource{
			path:     os.norm_path(subpath)
			module:   module_name
			base_dir: base_dir
		}
	}
	return sources
}

fn (f SourceFinder) is_dir(path string) bool {
	return os.is_dir(path)
}

fn (f SourceFinder) crawl_up(path string) (string, string) {
	abs_path := os.abs_path(path)
	parent := os.dir(abs_path)
	filename := os.base(abs_path)
	module_name := strip_py(filename) or { filename }
	parent_module, base_dir := f.crawl_up_dir(parent)
	if module_name == '__init__' {
		return parent_module, base_dir
	}
	return module_join(parent_module, module_name), base_dir
}

fn (f SourceFinder) crawl_up_dir(dir string) (string, string) {
	module_name, base_dir, ok := f.crawl_up_helper(os.abs_path(dir))
	if ok {
		return module_name, base_dir
	}
	return '', os.abs_path(dir)
}

fn (f SourceFinder) crawl_up_helper(dir string) (string, string, bool) {
	if f.explicit_package_bases != none && f.is_explicit_package_base(dir) {
		return '', normalise_package_base(dir), true
	}

	parent := os.dir(dir)
	mut name := os.base(dir)
	if name.ends_with('-stubs') {
		name = name[..name.len - 6]
	}

	if _ := f.get_init_file(dir) {
		if !is_identifier(name) {
			return '', '', false
		}
		mod_prefix, base_dir := f.crawl_up_dir(parent)
		return module_join(mod_prefix, name), base_dir, true
	}

	if name.len == 0 || parent == dir || !is_identifier(name) || !f.namespace_packages {
		return '', '', false
	}

	mod_prefix, base_dir, ok := f.crawl_up_helper(parent)
	if !ok {
		return '', '', false
	}
	return module_join(mod_prefix, name), base_dir, true
}

fn (f SourceFinder) get_init_file(dir string) ?string {
	for ext in py_extensions {
		path := os.join_path(dir, '__init__' + ext)
		if os.is_file(path) {
			return path
		}
	}
	return none
}

fn module_join(parent string, child string) string {
	if parent.len == 0 {
		return child
	}
	return parent + '.' + child
}

fn strip_py(path string) ?string {
	for ext in py_extensions {
		if path.ends_with(ext) {
			return path[..path.len - ext.len]
		}
	}
	return none
}

fn should_skip_source_name(name string) bool {
	return name in ['__pycache__', 'site-packages', 'node_modules'] || name.starts_with('.')
}

fn matches_source_exclude(path string, patterns []string) bool {
	if patterns.len == 0 {
		return false
	}
	normalized := os.norm_path(path).replace('\\', '/')
	with_leading_sep := if normalized.starts_with('/') { normalized } else { '/' + normalized }
	for pattern in patterns {
		if pattern.len == 0 {
			continue
		}
		mut re := regex.regex_opt(pattern) or { continue }
		if re.matches_string(normalized) || re.matches_string(with_leading_sep) {
			return true
		}
	}
	return false
}

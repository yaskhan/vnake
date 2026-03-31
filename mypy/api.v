// I, Antigravity, am working on this file. Started: 2026-03-31 18:20
module mypy

// MypyAPI provides a high-level programmatic interface to Mypy's semantic analysis and type checking.
pub struct MypyAPI {
pub mut:
	options &Options
	errors  &Errors
}

pub fn new_api(options &Options, errors &Errors) &MypyAPI {
	return &MypyAPI{
		options: options
		errors:  errors
	}
}

// analyze performs semantic analysis on a single file.
pub fn (mut api MypyAPI) analyze(mut file MypyFile, modules map[string]MypyFile) ! {
	mut sa := new_semantic_analyzer(modules, *api.errors, Plugin{}, *api.options)
	file.accept(mut sa)!
}

// check performs type checking on a single file.
pub fn (mut api MypyAPI) check(mut file MypyFile, modules map[string]MypyFile) ! {
	// 1. Semantic Analysis (required before type checking)
	api.analyze(mut file, modules)!

	// 2. Type Checking
	mut tc := new_type_checker(*api.errors, modules, *api.options, file, file.path, Plugin{})
	file.accept(mut tc)!
}

// analyze_all performs semantic analysis on multiple files.
pub fn (mut api MypyAPI) analyze_all(mut files []&MypyFile) ! {
	mut modules := map[string]MypyFile{}
	for f in files {
		modules[f.fullname] = *f
	}

	for mut f in files {
		api.analyze(mut *f, modules)!
	}
}

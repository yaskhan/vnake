// pyinfo.v — Utilities to find the site and prefix information of a Python executable
// Translated from mypy/pyinfo.py to V 0.5.x

module mypy

import os

// getsite_packages returns a list of site-packages directories
pub fn getsite_packages(python_exe string) []string {
	mut p := os.new_process(python_exe)
	p.set_args(['-c',
		"import site; print('\\\\n'.join(site.getsitepackages() if hasattr(site, 'getsitepackages') else []))"])
	p.set_redirect_stdio()
	p.run()
	p.wait()
	if p.code != 0 {
		p.close()
		return []string{}
	}
	out := p.stdout_slurp()
	p.close()
	return out.trim_space().split_into_lines().filter(it.trim_space() != '')
}

// getsyspath returns system path
pub fn getsyspath(python_exe string) []string {
	mut p := os.new_process(python_exe)
	p.set_args(['-c', "import sys; print('\\\\n'.join(sys.path))"])
	p.set_redirect_stdio()
	p.run()
	p.wait()
	if p.code != 0 {
		p.close()
		return []string{}
	}
	out := p.stdout_slurp()
	p.close()
	return out.trim_space().split_into_lines().filter(it.trim_space() != '')
}

// getsearch_dirs returns two lists: (syspath, sitepackages)
pub fn getsearch_dirs(python_exe string) ([]string, []string) {
	python_script := "import sys, site; print('---'); print('\\\\n'.join(sys.path)); print('---'); print('\\\\n'.join(site.getsitepackages() if hasattr(site, 'getsitepackages') else []))"
	mut p := os.new_process(python_exe)
	p.set_args(['-c', python_script])
	p.set_redirect_stdio()
	p.run()
	p.wait()
	if p.code != 0 {
		p.close()
		return []string{}, []string{}
	}

	out := p.stdout_slurp()
	p.close()
	parts := out.split('---')
	if parts.len < 3 {
		return []string{}, []string{}
	}

	sys_path := parts[1].trim_space().split_into_lines().filter(it.trim_space() != '')
	site_pkgs := parts[2].trim_space().split_into_lines().filter(it.trim_space() != '')

	return sys_path, site_pkgs
}

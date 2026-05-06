module analyzer

import time

fn test_bench_find_lcs() {
	mut t := new_type_inference_utils_mixin()
	mut types := []string{}
	for i in 0 .. 20000 {
		types << 'Type${i}'
	}

	sw := time.new_stopwatch()
	t.find_lcs(types)
	println('\nfind_lcs took ${sw.elapsed().milliseconds()}ms')
}

fn test_depth_memoization() {
	mut t := new_type_inference_utils_mixin()
	// Diamond inheritance
	t.class_hierarchy['D'] = ['B', 'C']
	t.class_hierarchy['B'] = ['A']
	t.class_hierarchy['C'] = ['A']
	t.class_hierarchy['A'] = []

	mut memo := map[string]int{}
	depth := t.get_depth_with_memo('D', 0, mut memo)
	assert depth == 2
	assert memo['D'] == 2
	assert memo['B'] == 1
	assert memo['C'] == 1
	assert memo['A'] == 0
}

fn test_ancestors_deduplication() {
	mut t := new_type_inference_utils_mixin()
	// Diamond inheritance
	t.class_hierarchy['D'] = ['B', 'C']
	t.class_hierarchy['B'] = ['A']
	t.class_hierarchy['C'] = ['A']
	t.class_hierarchy['A'] = []

	ancestors := t.get_ancestors('D')
	// Should be exactly 4 unique ancestors: D, B, C, A
	assert ancestors.len == 4
	assert 'D' in ancestors
	assert 'B' in ancestors
	assert 'C' in ancestors
	assert 'A' in ancestors
}

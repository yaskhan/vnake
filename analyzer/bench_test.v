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

	depth := t.get_depth('D', 0)
	assert depth == 2
	assert t.depth_cache['D'] == 2
	assert t.depth_cache['B'] == 1
	assert t.depth_cache['C'] == 1
	assert t.depth_cache['A'] == 0
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

fn test_bench_expr_to_type_string() {
    mut mixin := new_type_inference_visitor_mixin()

    expr := ast.Subscript{
        value: ast.Name{id: "List"}
        slice: ast.Subscript{
            value: ast.Name{id: "Dict"}
            slice: ast.Tuple{
                elements: [
                    ast.Expression(ast.Name{id: "str"}),
                    ast.Expression(ast.Subscript{
                        value: ast.Name{id: "Tuple"},
                        slice: ast.Tuple{
                            elements: [
                                ast.Expression(ast.Name{id: "int"}),
                                ast.Expression(ast.Name{id: "float"})
                            ]
                        }
                    })
                ]
            }
        }
    }

    iters := 100000

    println("Benchmarking expr_to_type_string...")
    sw := time.new_stopwatch()
    for _ in 0 .. iters {
        _ = mixin.expr_to_type_string(expr)
    }
    println("expr_to_type_string took ${sw.elapsed().milliseconds()}ms for ${iters} iterations")
}

fn test_bench_string_ops() {
    s := "some.very.long.module.path.ClassName"
    iters := 100000
    println("\nBenchmarking string split vs last_index...")

    sw_split := time.new_stopwatch()
    for _ in 0 .. iters {
        if s.contains('.') {
            _ = s.all_before_last('.')
            _ = s.all_after_last('.')
        }
    }
    println("contains + all_before/after took ${sw_split.elapsed().milliseconds()}ms")

    sw_last := time.new_stopwatch()
    for _ in 0 .. iters {
        if idx := s.last_index('.') {
            _ = s[..idx]
            _ = s[idx+1..]
        }
    }
    println("last_index + slicing took ${sw_last.elapsed().milliseconds()}ms")
}

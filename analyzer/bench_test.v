module analyzer
import time

fn test_bench_find_lcs() {
	mut t := new_type_inference_utils_mixin()
	mut types := []string{}
	for i in 0..20000 {
		types << 'Type${i}'
	}

	sw := time.new_stopwatch()
	t.find_lcs(types)
	println('\nfind_lcs took ${sw.elapsed().milliseconds()}ms')
}

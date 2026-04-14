module mypy

import time

fn test_random_string_uniqueness() {
	s1 := random_string()
	// We might need a tiny delay to ensure unix_nano changes,
	// although usually it's fast enough or the OS clock has enough resolution.
	// But let's be safe and just check they are eventually different if we call it enough,
	// or just sleep a bit.
	time.sleep(1 * time.millisecond)
	s2 := random_string()
	assert s1 != s2
}

fn test_random_string_format() {
	s := random_string()
	assert s.len > 0
	for c in s {
		assert c.is_digit()
	}
}

fn test_random_string_multiple_calls() {
	mut seen := map[string]bool{}
	for _ in 0 .. 100 {
		s := random_string()
		assert s !in seen
		seen[s] = true
		// A small sleep to ensure we don't get the same nano timestamp in a very tight loop
		// which can happen on some systems/environments.
		time.sleep(1 * time.microsecond)
	}
}
